import re
import librosa
import numpy as np

from .config import settings

_WHISPER_MODEL = None

FIRST_PERSON_WORDS = {"i", "me", "my", "mine", "myself", "main", "maine", "mera", "meri", "mujhe"}
HEDGE_WORDS = {"maybe", "perhaps", "probably", "basically", "honestly", "shayad", "matlab", "lagta", "pata"}


def _transcribe_if_enabled(audio_path: str) -> str:
    """Optional lazy Faster-Whisper transcription (enabled via ENABLE_WHISPER=true)."""
    global _WHISPER_MODEL
    if not settings.enable_whisper:
        return ""
    try:
        from faster_whisper import WhisperModel

        if _WHISPER_MODEL is None:
            _WHISPER_MODEL = WhisperModel(settings.whisper_model_size, device="cpu", compute_type="int8")
        segments, _ = _WHISPER_MODEL.transcribe(audio_path, beam_size=1)
        return " ".join(seg.text.strip() for seg in segments if seg.text).strip()
    except Exception:
        return ""


def analyze_linguistic_cues(transcript: str, question: str = "") -> dict:
    """Analyze pronoun avoidance, question repetition, and over-explaining ratio."""
    words = re.findall(r"[a-zA-Z]+", (transcript or "").lower())
    q_words = set(re.findall(r"[a-zA-Z]{3,}", (question or "").lower()))
    wc = len(words)
    if wc == 0:
        return {
            "word_count": 0,
            "pronoun_rate_pct": 0.0,
            "pronoun_avoidance_flag": False,
            "question_repetition_ratio": 0.0,
            "over_explaining_ratio": 0.0,
            "hedge_count": 0,
        }

    first_person_hits = sum(1 for w in words if w in FIRST_PERSON_WORDS)
    pronoun_rate = round((first_person_hits / wc) * 100.0, 1)
    hedge_count = sum(1 for w in words if w in HEDGE_WORDS)

    overlap = sum(1 for w in words[:12] if w in q_words) if q_words else 0
    q_rep = round(min(100.0, (overlap / max(1, len(q_words))) * 100.0), 1)
    over_explain = round(min(100.0, max(0.0, (wc - 26) * 2.2)), 1)

    return {
        "word_count": wc,
        "pronoun_rate_pct": pronoun_rate,
        "pronoun_avoidance_flag": wc >= 10 and pronoun_rate < 3.5,
        "question_repetition_ratio": q_rep,
        "over_explaining_ratio": over_explain,
        "hedge_count": hedge_count,
    }


def analyze_audio(audio_path: str, question: str = "", transcript_hint: str = "") -> dict:
    """Extract 7 bio-acoustic, micro-tremor, formant, breathing, speech-rate, and voice-clone indicators."""
    y, sr = librosa.load(audio_path, sr=16000, mono=True)
    duration_sec = round(float(len(y) / sr), 2) if sr > 0 else 0.0

    if len(y) < sr * 0.25:
        return _empty_audio_metrics(duration_sec)

    hop_length = 512
    frame_rate = sr / hop_length  # ~31.25 Hz
    rms = librosa.feature.rms(y=y, hop_length=hop_length)[0]
    rms_mean = float(np.mean(rms))
    rms_std = float(np.std(rms))
    silence_threshold = max(0.005, rms_mean * 0.32)
    pause_ratio = round(float(np.mean(rms < silence_threshold)) * 100.0, 1)

    spike_threshold = rms_mean + (1.5 * rms_std)
    energy_spike_rate = round(float(np.mean(rms > spike_threshold)) * 100.0, 1)

    # 15. Response Latency (ms silence gap before speech onset)
    voiced_indices = np.where(rms > silence_threshold * 1.25)[0]
    first_speech_sec = float(voiced_indices[0] / frame_rate) if len(voiced_indices) > 0 else 0.0
    response_latency_ms = round(first_speech_sec * 1000.0, 0)

    # 17. Pitch (F0) Jitter & Amplitude Shimmer
    f0 = librosa.yin(y, fmin=70, fmax=380, sr=sr, hop_length=hop_length)
    voiced = f0[(f0 > 75) & (f0 < 370) & (rms > silence_threshold)]
    pitch_mean = round(float(np.mean(voiced)), 1) if len(voiced) > 0 else 0.0
    pitch_std = round(float(np.std(voiced)), 1) if len(voiced) > 0 else 0.0

    if len(voiced) > 3 and pitch_mean > 0:
        pitch_jitter_pct = round(float(np.mean(np.abs(np.diff(voiced))) / pitch_mean) * 100.0, 2)
    else:
        pitch_jitter_pct = 0.0

    voiced_rms = rms[rms > silence_threshold]
    if len(voiced_rms) > 3 and float(np.mean(voiced_rms)) > 1e-6:
        amplitude_shimmer_pct = round(
            float(np.mean(np.abs(np.diff(voiced_rms))) / float(np.mean(voiced_rms))) * 100.0, 2
        )
    else:
        amplitude_shimmer_pct = 0.0

    # 16. Voice Micro-Tremor (8–12 Hz vocal cord oscillation via FFT on amplitude envelope)
    env = rms - np.mean(rms)
    fft_env = np.abs(np.fft.rfft(env * np.hanning(len(env))))
    env_freqs = np.fft.rfftfreq(len(env), d=1.0 / frame_rate)
    tremor_mask = (env_freqs >= 8.0) & (env_freqs <= 12.0)
    total_power = float(np.sum(fft_env) + 1e-6)
    micro_tremor_index = round(
        min(100.0, (float(np.sum(fft_env[tremor_mask])) / total_power) * 320.0), 1
    ) if np.any(tremor_mask) else 12.0

    # 18. Formant Frequency Shift proxy (Spectral Centroid & Bandwidth F1/F2 constriction)
    centroid = librosa.feature.spectral_centroid(y=y, sr=sr, hop_length=hop_length)[0]
    voiced_cent = centroid[rms > silence_threshold]
    formant_center_hz = round(float(np.mean(voiced_cent)), 1) if len(voiced_cent) > 0 else 1450.0
    formant_shift_index = round(min(100.0, (float(np.std(voiced_cent)) / max(formant_center_hz, 400.0)) * 220.0), 1) if len(voiced_cent) > 2 else 15.0

    # 19. Breathing Pattern & Sharp Inhalations (low-energy high-ZCR bursts before speech)
    zcr = librosa.feature.zero_crossing_rate(y=y, hop_length=hop_length)[0]
    breath_frames = (rms > silence_threshold * 0.45) & (rms < rms_mean * 0.95) & (zcr > 0.14)
    sharp_inhalations = int(np.sum(np.diff(breath_frames.astype(int)) == 1))
    breathing_irregularity = round(min(100.0, sharp_inhalations * 14.0 + max(0.0, pause_ratio - 30.0)), 1)

    # 20. Speech Rate Acceleration / Deceleration (syllable onsets per second)
    onset_env = librosa.onset.onset_strength(y=y, sr=sr, hop_length=hop_length)
    onsets = librosa.onset.onset_detect(onset_envelope=onset_env, sr=sr, hop_length=hop_length, units="time")
    active_sec = max(0.5, duration_sec * (1.0 - pause_ratio / 100.0))
    speech_rate_wps = round((len(onsets) / 1.65) / active_sec, 2)
    if len(onsets) > 4:
        ioi = np.diff(onsets)
        speech_rate_variance = round(min(100.0, float(np.std(ioi) / (np.mean(ioi) + 1e-4)) * 65.0), 1)
    else:
        speech_rate_variance = 15.0

    # 21. Transcript & Linguistic cues (optional Faster-Whisper + hint)
    transcript = (transcript_hint or "").strip() or _transcribe_if_enabled(audio_path)
    linguistic = analyze_linguistic_cues(transcript, question)

    # Media Authenticity: Voice Clone Check (spectral flatness + micro-breath presence)
    flatness = librosa.feature.spectral_flatness(y=y, hop_length=hop_length)[0]
    mean_flatness = float(np.mean(flatness))
    # Cloned/synthetic TTS voices tend to have abnormally uniform pitch jitter (<0.4%) or unusual spectral flatness
    flatness_penalty = max(0.0, (mean_flatness - 0.12) * 160.0)
    robotic_penalty = 18.0 if (pitch_jitter_pct < 0.35 and len(voiced) > 8) else 0.0
    breath_bonus = 6.0 if sharp_inhalations >= 1 else 0.0
    human_voice_pct = round(max(15.0, min(99.0, 91.0 + breath_bonus - flatness_penalty - robotic_penalty)), 1)
    voice_clone_risk_pct = round(100.0 - human_voice_pct, 1)

    # Vocal stress composite
    pitch_instability = min(100.0, (pitch_std / max(pitch_mean, 120.0)) * 220.0) if pitch_mean > 0 else 20.0
    pause_anomaly = min(100.0, max(0.0, (pause_ratio - 22.0) * 1.8))
    energy_volatility = min(100.0, energy_spike_rate * 4.2)

    vocal_stress = round(
        min(
            100.0,
            0.28 * pitch_instability
            + 0.20 * micro_tremor_index
            + 0.18 * energy_volatility
            + 0.18 * pause_anomaly
            + 0.16 * formant_shift_index,
        ),
        1,
    )

    frames_per_sec = max(1, int(round(sr / hop_length)))
    timeline = []
    for sec in range(max(1, int(np.ceil(duration_sec)))):
        start = sec * frames_per_sec
        end = min(len(rms), (sec + 1) * frames_per_sec)
        if start >= end:
            break
        bucket_rms = float(np.mean(rms[start:end]))
        bucket_f0 = f0[start:end]
        valid_f0 = bucket_f0[(bucket_f0 > 75) & (bucket_f0 < 370)]
        timeline.append(
            {
                "t": float(sec),
                "energy": round(min(100.0, bucket_rms * 650.0), 1),
                "pitch_hz": round(float(np.mean(valid_f0)), 1) if len(valid_f0) > 0 else 0.0,
            }
        )

    return {
        "duration_sec": duration_sec,
        "pitch_mean_hz": pitch_mean,
        "pitch_std_hz": pitch_std,
        "energy_rms_mean": round(rms_mean, 4),
        "energy_spike_rate": energy_spike_rate,
        "pause_ratio": pause_ratio,
        # 15-21 Forensic audio indicators
        "response_latency_ms": response_latency_ms,
        "first_speech_sec": round(first_speech_sec, 2),
        "voice_micro_tremor_index": micro_tremor_index,
        "pitch_jitter_pct": pitch_jitter_pct,
        "amplitude_shimmer_pct": amplitude_shimmer_pct,
        "formant_center_hz": formant_center_hz,
        "formant_shift_index": formant_shift_index,
        "sharp_inhalations": sharp_inhalations,
        "breathing_irregularity": breathing_irregularity,
        "speech_rate_wps": speech_rate_wps,
        "speech_rate_variance": speech_rate_variance,
        "transcript": transcript,
        "linguistic": linguistic,
        # Voice Clone Authenticity
        "human_voice_pct": human_voice_pct,
        "voice_clone_risk_pct": voice_clone_risk_pct,
        "vocal_stress_index": vocal_stress,
        "audio_available": True,
        "timeline": timeline[:120],
    }


def _empty_audio_metrics(duration_sec: float = 0.0) -> dict:
    return {
        "duration_sec": duration_sec,
        "pitch_mean_hz": 0.0,
        "pitch_std_hz": 0.0,
        "energy_rms_mean": 0.0,
        "energy_spike_rate": 0.0,
        "pause_ratio": 100.0,
        "response_latency_ms": 0.0,
        "first_speech_sec": 0.0,
        "voice_micro_tremor_index": 0.0,
        "pitch_jitter_pct": 0.0,
        "amplitude_shimmer_pct": 0.0,
        "formant_center_hz": 0.0,
        "formant_shift_index": 0.0,
        "sharp_inhalations": 0,
        "breathing_irregularity": 0.0,
        "speech_rate_wps": 0.0,
        "speech_rate_variance": 0.0,
        "transcript": "",
        "linguistic": analyze_linguistic_cues(""),
        "human_voice_pct": 50.0,
        "voice_clone_risk_pct": 50.0,
        "vocal_stress_index": 0.0,
        "audio_available": False,
        "timeline": [],
    }
