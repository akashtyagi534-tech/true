import librosa
import numpy as np


def analyze_audio(audio_path: str) -> dict:
    y, sr = librosa.load(audio_path, sr=16000, mono=True)
    duration_sec = round(float(len(y) / sr), 2) if sr > 0 else 0.0

    if len(y) < sr * 0.25:
        return {
            "duration_sec": duration_sec,
            "pitch_mean_hz": 0.0,
            "pitch_std_hz": 0.0,
            "energy_rms_mean": 0.0,
            "energy_spike_rate": 0.0,
            "pause_ratio": 100.0,
            "vocal_stress_index": 0.0,
            "audio_available": False,
            "timeline": [],
        }

    # RMS energy per frame
    hop_length = 512
    rms = librosa.feature.rms(y=y, hop_length=hop_length)[0]
    rms_mean = float(np.mean(rms))
    rms_std = float(np.std(rms))
    silence_threshold = max(0.005, rms_mean * 0.32)
    pause_ratio = round(float(np.mean(rms < silence_threshold)) * 100.0, 1)

    spike_threshold = rms_mean + (1.5 * rms_std)
    energy_spike_rate = round(float(np.mean(rms > spike_threshold)) * 100.0, 1)

    # Fundamental frequency estimation (F0) via YIN
    f0 = librosa.yin(y, fmin=70, fmax=380, sr=sr, hop_length=hop_length)
    voiced = f0[(f0 > 75) & (f0 < 370) & (rms > silence_threshold)]
    pitch_mean = round(float(np.mean(voiced)), 1) if len(voiced) > 0 else 0.0
    pitch_std = round(float(np.std(voiced)), 1) if len(voiced) > 0 else 0.0

    # Normalize acoustic indicators
    pitch_instability = min(100.0, (pitch_std / max(pitch_mean, 120.0)) * 220.0) if pitch_mean > 0 else 20.0
    pause_anomaly = min(100.0, max(0.0, (pause_ratio - 22.0) * 1.8))
    energy_volatility = min(100.0, energy_spike_rate * 4.5)

    vocal_stress = round(
        min(100.0, 0.45 * pitch_instability + 0.30 * energy_volatility + 0.25 * pause_anomaly),
        1,
    )

    # Downsample timeline to ~1s buckets
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
        timeline.append({
            "t": float(sec),
            "energy": round(min(100.0, bucket_rms * 650.0), 1),
            "pitch_hz": round(float(np.mean(valid_f0)), 1) if len(valid_f0) > 0 else 0.0,
        })

    return {
        "duration_sec": duration_sec,
        "pitch_mean_hz": pitch_mean,
        "pitch_std_hz": pitch_std,
        "energy_rms_mean": round(rms_mean, 4),
        "energy_spike_rate": energy_spike_rate,
        "pause_ratio": pause_ratio,
        "vocal_stress_index": vocal_stress,
        "audio_available": True,
        "timeline": timeline[:120],
    }
