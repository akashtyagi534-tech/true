import math

WEIGHTS: dict[str, float] = {
    "blink_rate": 0.85,
    "gaze_off_ratio": 1.25,
    "head_yaw_std": 0.80,
    "head_pitch_std": 0.55,
    "brow_inner_up": 0.55,
    "mouth_press": 0.75,
    "jaw_clench": 0.65,
    "smile_asymmetry": 0.60,
    "pitch_std": 0.90,
    "voice_jitter": 0.70,
    "speech_rate": 0.45,
    "hedge_rate": 1.40,
    "filler_rate": 0.80,
    "distancing_rate": 0.65,
    "pause_ratio": 1.00,
    "bpm_delta": 0.85,
    "response_latency": 0.90,
    "detail_score": -0.95,
}

BIAS = -0.10

SIGNAL_LABELS = {
    "blink_rate": "blink rate up",
    "gaze_off_ratio": "gaze aversion",
    "head_yaw_std": "head turning",
    "head_pitch_std": "head nodding",
    "brow_inner_up": "brow tension",
    "mouth_press": "lip pressing",
    "jaw_clench": "jaw tension",
    "smile_asymmetry": "asymmetric smile",
    "pitch_std": "voice pitch swing",
    "voice_jitter": "voice tremor",
    "speech_rate": "speech rush",
    "hedge_rate": "hedging words",
    "filler_rate": "fillers",
    "distancing_rate": "distancing language",
    "pause_ratio": "long pauses",
    "bpm_delta": "heart rate spike",
    "response_latency": "delayed answer",
    "detail_score": "low detail",
}

SIGNAL_HINGLISH = {
    "blink_rate": "aankhein tezi se jhapak rahi hain",
    "gaze_off_ratio": "nazar baar-baar camera se hat rahi hai",
    "head_yaw_std": "sir idhar-udhar ghum raha hai",
    "head_pitch_std": "sir mein ajeeb movement hai",
    "brow_inner_up": "maathe aur eyebrows par tension hai",
    "mouth_press": "hoth tight dab rahe hain",
    "jaw_clench": "jabda tight ho raha hai",
    "smile_asymmetry": "smile natural nahi, ek taraf jhuki hai",
    "pitch_std": "awaaz ka pitch achanak badal raha hai",
    "voice_jitter": "awaaz mein halka kampan hai",
    "speech_rate": "bolne ki speed achanak badh gayi",
    "hedge_rate": "'shayad' ya 'matlab' jaise taal-matol wale shabd use hue",
    "filler_rate": "'umm/uhh' jaise fillers zyada aa rahe hain",
    "distancing_rate": "baat ko khud se door rakhne wale shabd use hue",
    "pause_ratio": "jawab mein lambe pauses aa rahe hain",
    "bpm_delta": "dil ki dhadkan baseline se tez ho gayi",
    "response_latency": "sawaal ke baad jawab dene mein deri hui",
    "detail_score": "jawab mein exact details ya numbers ki kami hai",
}

CROSS_QUESTIONS = {
    "hedge_rate": "Tumne pakka jawab nahi diya — bina 'shayad' bole, exact haan ya na mein batao.",
    "detail_score": "Is baat mein koi exact time, naam ya number nahi aaya — poori detail step-by-step batao.",
    "gaze_off_ratio": "Camera mein seedha dekh kar yahi baat dobara bolo — kya kuch chhupa rahe ho?",
    "response_latency": "Jawab dene se pehle itna sochna kyun pada? Pehla khayal kya aaya tha?",
    "pause_ratio": "Beech mein ruk kyun gaye? Is kahani ka kaunsa hissa yaad nahi aa raha?",
    "bpm_delta": "Is sawaal pe tumhara stress aur pulse dono badh gaye — sach-sach batao isme kya baat hai?",
    "mouth_press": "Aisa lag raha hai kuch bolte-bolte rok liya — jo dimaag mein tha woh poora bolo.",
    "pitch_std": "Is point pe awaaz badal gayi — is event ko ulte order (last se start) mein sunao.",
}

CLAMP = 3.0


def _sigmoid(x: float) -> float:
    x = max(-50.0, min(50.0, x))
    return 1.0 / (1.0 + math.exp(-x))


def build_baseline(samples: list[dict]) -> dict:
    if not samples:
        return {}
    keys = {k for s in samples for k in s}
    baseline: dict[str, tuple[float, float]] = {}
    for key in keys:
        values = [float(s[key]) for s in samples if s.get(key) is not None]
        if len(values) < 2:
            continue
        mean = sum(values) / len(values)
        var = sum((v - mean) ** 2 for v in values) / (len(values) - 1)
        baseline[key] = (mean, math.sqrt(var))
    return baseline


def _z(value: float, mean: float, std: float) -> float:
    floor = max(abs(mean) * 0.20, 0.02)
    spread = std if std > 1e-6 else floor
    return max(-CLAMP, min(CLAMP, (value - mean) / spread))


def build_verdict_and_followup(
    score: float, top_keys: list[str]
) -> tuple[str, str | None]:
    reasons = [SIGNAL_HINGLISH[k] for k in top_keys if k in SIGNAL_HINGLISH][:2]
    reason_str = " aur ".join(reasons)

    if score >= 62:
        if reason_str:
            verdict = f"Dhyan do, yahan jhoot ya zyada stress lag raha hai — kyunki {reason_str}."
        else:
            verdict = "Dhyan do, yahan baseline ke mukable kaafi stress spike mila hai."
        followup = None
        for k in top_keys:
            if k in CROSS_QUESTIONS:
                followup = CROSS_QUESTIONS[k]
                break
        if not followup:
            followup = "Is baat ko dobara exact timeline aur proof ke saath explain karo."
        return verdict, followup

    if score >= 45:
        if reason_str:
            verdict = f"Thoda hesitation ya confusion lag raha hai — kyunki {reason_str}."
        else:
            verdict = "Jawab thoda mixed lag raha hai, ek follow-up sawaal poochna theek rahega."
        return verdict, None

    return "Ye jawab natural aur sahi lag raha hai — chehra aur awaaz baseline ke hisaab se normal hain.", None


def score_window(
    features: dict, baseline: dict, coverage: float, window_count: int
) -> tuple[float | None, float | None, list[str], str, str | None, dict[str, float]]:
    if window_count < 4 or coverage < 0.35:
        return None, None, [], "", None, {}

    contributions: dict[str, float] = {}
    total = BIAS
    for key, weight in WEIGHTS.items():
        if features.get(key) is None:
            continue
        val = float(features[key])

        if key == "bpm_delta":
            if val > 6.0:
                z = min(CLAMP, (val - 4.0) / 8.0)
                part = weight * z
                contributions[key] = part
                total += part
            continue
        if key == "response_latency":
            if val > 2.8:
                z = min(CLAMP, (val - 2.0) / 2.0)
                part = weight * z
                contributions[key] = part
                total += part
            continue

        if key not in baseline:
            continue
        mean, std = baseline[key]
        z = _z(val, mean, std)
        part = weight * z
        contributions[key] = part
        total += part

    probability = _sigmoid(total)
    score = round(probability * 100, 1)

    coverage_factor = min(1.0, coverage / 0.85)
    volume_factor = min(1.0, window_count / 10.0)
    certainty = 1.0 - abs(probability - 0.5) * 2.0
    confidence = round(
        100 * (0.25 + 0.75 * certainty) * coverage_factor * (0.5 + 0.5 * volume_factor), 1
    )

    ranked_keys = [
        k
        for k, v in sorted(contributions.items(), key=lambda kv: kv[1], reverse=True)
        if v >= 0.30
    ][:3]

    signals = [SIGNAL_LABELS[k] for k in ranked_keys if k in SIGNAL_LABELS]
    verdict_text, followup = build_verdict_and_followup(score, ranked_keys)

    def _chan(keys: list[str]) -> int:
        s = sum(max(0.0, contributions.get(k, 0.0)) for k in keys)
        return int(min(100, round(_sigmoid(s - 0.5) * 100)))

    radar = {
        "eyes": _chan(["blink_rate", "gaze_off_ratio"]),
        "face": _chan(["brow_inner_up", "mouth_press", "jaw_clench", "smile_asymmetry", "head_yaw_std"]),
        "voice": _chan(["pitch_std", "voice_jitter", "speech_rate", "pause_ratio"]),
        "words": _chan(["hedge_rate", "filler_rate", "distancing_rate", "detail_score"]),
        "bio": _chan(["bpm_delta", "response_latency"]),
    }

    return score, confidence, signals, verdict_text, followup, radar


def confidence_label(confidence: float | None, coverage: float) -> str:
    if coverage < 0.5:
        return "LOW"
    if confidence is None:
        return "LOW"
    if confidence >= 65:
        return "HIGH"
    if confidence >= 40:
        return "MEDIUM"
    return "LOW"


def overall_verdict_label(overall_score: float | None, spikes_count: int) -> str:
    if overall_score is None:
        return "DATA KAM HAI (INSUFFICIENT)"
    if overall_score >= 62 or spikes_count >= 4:
        return "HIGH STRESS / SUSPICIOUS PATTERNS"
    if overall_score >= 45 or spikes_count >= 2:
        return "MIXED / MODERATE HESITATION"
    return "NATURAL / CONSISTENT"


def _status_level(val: float, warn: float, high: float) -> str:
    if val >= high:
        return "high"
    if val >= warn:
        return "elevated"
    return "normal"


def build_21_point_indicators(
    target_v: dict,
    target_a: dict,
    baseline_v: dict | None = None,
    baseline_a: dict | None = None,
) -> list[dict]:
    """Build all 21 multi-modal indicators with Stage 1 Baseline vs Stage 2 Target deltas."""
    bv = baseline_v or {}
    ba = baseline_a or {}

    def _delta(t_val: float, b_key: str, src: dict, default_base: float) -> float:
        base = float(src.get(b_key, default_base))
        return round(t_val - base, 1)

    bpm_target = float(target_v.get("rppg_bpm", 74.0))
    bpm_delta = _delta(bpm_target, "rppg_bpm", bv, 72.0)

    av_sync_ms = round(
        abs(float(target_v.get("first_expression_sec", 0.4)) - float(target_a.get("first_speech_sec", 0.3))) * 1000.0,
        0,
    )
    ling = target_a.get("linguistic") or {}

    return [
        # A. Ocular & Micro-Expression (1-8)
        {
            "id": 1,
            "category": "Ocular & Micro-Expressions",
            "name": "Blink Rate Spike (EAR)",
            "value": f"{target_v.get('blink_rate_per_min', 0.0)} /min",
            "delta": f"{_delta(float(target_v.get('blink_rate_per_min', 0.0)), 'blink_rate_per_min', bv, 16.0):+.1f}",
            "status": _status_level(abs(float(target_v.get("blink_rate_per_min", 16.0)) - 17.0), 8, 14),
        },
        {
            "id": 2,
            "category": "Ocular & Micro-Expressions",
            "name": "Blink Duration (Closure)",
            "value": f"{target_v.get('blink_duration_ms', 180.0)} ms",
            "delta": f"{_delta(float(target_v.get('blink_duration_ms', 180.0)), 'blink_duration_ms', bv, 180.0):+.0f} ms",
            "status": _status_level(float(target_v.get("blink_duration_ms", 180.0)), 260, 380),
        },
        {
            "id": 3,
            "category": "Ocular & Micro-Expressions",
            "name": "Pupil / Iris Dilation Ratio",
            "value": f"{target_v.get('pupil_dilation_ratio', 24.0)}%",
            "delta": f"{_delta(float(target_v.get('pupil_dilation_ratio', 24.0)), 'pupil_dilation_ratio', bv, 22.0):+.1f}%",
            "status": _status_level(float(target_v.get("pupil_dilation_ratio", 24.0)), 30, 42),
        },
        {
            "id": 4,
            "category": "Ocular & Micro-Expressions",
            "name": "Gaze Instability & Aversion",
            "value": f"{target_v.get('gaze_instability_index', 0.0)}% ({target_v.get('gaze_aversion_direction', 'Center')})",
            "delta": f"{_delta(float(target_v.get('gaze_instability_index', 0.0)), 'gaze_instability_index', bv, 18.0):+.1f}%",
            "status": _status_level(float(target_v.get("gaze_instability_index", 0.0)), 38, 62),
        },
        {
            "id": 5,
            "category": "Ocular & Micro-Expressions",
            "name": "Lip Compression & Tension",
            "value": f"{target_v.get('lip_compression_index', 0.0)}%",
            "delta": f"{_delta(float(target_v.get('lip_compression_index', 0.0)), 'lip_compression_index', bv, 22.0):+.1f}%",
            "status": _status_level(float(target_v.get("lip_compression_index", 0.0)), 42, 65),
        },
        {
            "id": 6,
            "category": "Ocular & Micro-Expressions",
            "name": "Eyebrow Asymmetry & Flashes",
            "value": f"{target_v.get('eyebrow_asymmetry_index', 0.0)}%",
            "delta": f"{_delta(float(target_v.get('eyebrow_asymmetry_index', 0.0)), 'eyebrow_asymmetry_index', bv, 15.0):+.1f}%",
            "status": _status_level(float(target_v.get("eyebrow_asymmetry_index", 0.0)), 35, 58),
        },
        {
            "id": 7,
            "category": "Ocular & Micro-Expressions",
            "name": "Nostril Flare",
            "value": f"{target_v.get('nostril_flare_index', 0.0)}%",
            "delta": f"{_delta(float(target_v.get('nostril_flare_index', 0.0)), 'nostril_flare_index', bv, 16.0):+.1f}%",
            "status": _status_level(float(target_v.get("nostril_flare_index", 0.0)), 38, 62),
        },
        {
            "id": 8,
            "category": "Ocular & Micro-Expressions",
            "name": "Duping Delight (Micro-Smile)",
            "value": f"{target_v.get('duping_delight_flashes', 0)} flashes",
            "delta": f"{int(target_v.get('duping_delight_flashes', 0)) - int(bv.get('duping_delight_flashes', 0)):+d}",
            "status": _status_level(float(target_v.get("duping_delight_flashes", 0)), 2, 4),
        },
        # B. Physiological & Kinesic (9-14)
        {
            "id": 9,
            "category": "Physiological & Kinesic",
            "name": "rPPG Heart Rate (BPM) Delta",
            "value": f"{bpm_target} BPM",
            "delta": f"{bpm_delta:+.1f} BPM",
            "status": _status_level(abs(bpm_delta), 8, 16),
        },
        {
            "id": 10,
            "category": "Physiological & Kinesic",
            "name": "Head Jitter & Sudden Tilt",
            "value": f"{target_v.get('head_jitter_index', 0.0)}%",
            "delta": f"{_delta(float(target_v.get('head_jitter_index', 0.0)), 'head_jitter_index', bv, 18.0):+.1f}%",
            "status": _status_level(float(target_v.get("head_jitter_index", 0.0)), 40, 65),
        },
        {
            "id": 11,
            "category": "Physiological & Kinesic",
            "name": "Postural Freeze / Rigidity",
            "value": f"{target_v.get('postural_freeze_index', 0.0)}%",
            "delta": f"{_delta(float(target_v.get('postural_freeze_index', 0.0)), 'postural_freeze_index', bv, 20.0):+.1f}%",
            "status": _status_level(float(target_v.get("postural_freeze_index", 0.0)), 48, 72),
        },
        {
            "id": 12,
            "category": "Physiological & Kinesic",
            "name": "Shoulder Shrug Asymmetry",
            "value": f"{target_v.get('shoulder_shrug_asymmetry', 0.0)}%",
            "delta": f"{_delta(float(target_v.get('shoulder_shrug_asymmetry', 0.0)), 'shoulder_shrug_asymmetry', bv, 12.0):+.1f}%",
            "status": _status_level(float(target_v.get("shoulder_shrug_asymmetry", 0.0)), 36, 60),
        },
        {
            "id": 13,
            "category": "Physiological & Kinesic",
            "name": "Hand-to-Face Self-Adaptors",
            "value": f"{target_v.get('hand_to_face_adaptors_pct', 0.0)}%",
            "delta": f"{_delta(float(target_v.get('hand_to_face_adaptors_pct', 0.0)), 'hand_to_face_adaptors_pct', bv, 5.0):+.1f}%",
            "status": _status_level(float(target_v.get("hand_to_face_adaptors_pct", 0.0)), 18, 38),
        },
        {
            "id": 14,
            "category": "Physiological & Kinesic",
            "name": "Swallowing / Larynx Motion",
            "value": f"{target_v.get('swallowing_larynx_spikes', 0)} pulses",
            "delta": f"{int(target_v.get('swallowing_larynx_spikes', 0)) - int(bv.get('swallowing_larynx_spikes', 0)):+d}",
            "status": _status_level(float(target_v.get("swallowing_larynx_spikes", 0)), 2, 5),
        },
        # C. Bio-Acoustic & Speech Forensics (15-21)
        {
            "id": 15,
            "category": "Bio-Acoustic & Speech",
            "name": "Response Latency (Delay)",
            "value": f"{int(target_a.get('response_latency_ms', 0))} ms",
            "delta": f"{_delta(float(target_a.get('response_latency_ms', 0)), 'response_latency_ms', ba, 320.0):+.0f} ms",
            "status": _status_level(float(target_a.get("response_latency_ms", 0)), 900, 1800),
        },
        {
            "id": 16,
            "category": "Bio-Acoustic & Speech",
            "name": "Voice Micro-Tremor (8-12 Hz)",
            "value": f"{target_a.get('voice_micro_tremor_index', 0.0)}%",
            "delta": f"{_delta(float(target_a.get('voice_micro_tremor_index', 0.0)), 'voice_micro_tremor_index', ba, 18.0):+.1f}%",
            "status": _status_level(float(target_a.get("voice_micro_tremor_index", 0.0)), 40, 62),
        },
        {
            "id": 17,
            "category": "Bio-Acoustic & Speech",
            "name": "Pitch (F0) Jitter & Shimmer",
            "value": f"{target_a.get('pitch_jitter_pct', 0.0)}% / {target_a.get('amplitude_shimmer_pct', 0.0)}%",
            "delta": f"{_delta(float(target_a.get('pitch_jitter_pct', 0.0)), 'pitch_jitter_pct', ba, 1.8):+.2f}%",
            "status": _status_level(float(target_a.get("pitch_jitter_pct", 0.0)), 4.5, 8.5),
        },
        {
            "id": 18,
            "category": "Bio-Acoustic & Speech",
            "name": "Formant Shift (F1/F2 Tension)",
            "value": f"{target_a.get('formant_center_hz', 0.0)} Hz ({target_a.get('formant_shift_index', 0.0)}%)",
            "delta": f"{_delta(float(target_a.get('formant_shift_index', 0.0)), 'formant_shift_index', ba, 16.0):+.1f}%",
            "status": _status_level(float(target_a.get("formant_shift_index", 0.0)), 38, 60),
        },
        {
            "id": 19,
            "category": "Bio-Acoustic & Speech",
            "name": "Breathing & Sharp Inhalations",
            "value": f"{target_a.get('sharp_inhalations', 0)} breaths ({target_a.get('breathing_irregularity', 0.0)}%)",
            "delta": f"{_delta(float(target_a.get('breathing_irregularity', 0.0)), 'breathing_irregularity', ba, 15.0):+.1f}%",
            "status": _status_level(float(target_a.get("breathing_irregularity", 0.0)), 40, 65),
        },
        {
            "id": 20,
            "category": "Bio-Acoustic & Speech",
            "name": "Speech Rate Acceleration",
            "value": f"{target_a.get('speech_rate_wps', 0.0)} wps (var {target_a.get('speech_rate_variance', 0.0)}%)",
            "delta": f"{_delta(float(target_a.get('speech_rate_wps', 0.0)), 'speech_rate_wps', ba, 2.2):+.2f} wps",
            "status": _status_level(float(target_a.get("speech_rate_variance", 0.0)), 42, 65),
        },
        {
            "id": 21,
            "category": "Bio-Acoustic & Speech",
            "name": "A/V Sync & Linguistic Cues",
            "value": f"Sync {int(av_sync_ms)}ms · Pronouns {ling.get('pronoun_rate_pct', 0.0)}%",
            "delta": "Pronoun drop" if ling.get("pronoun_avoidance_flag") else "Steady",
            "status": _status_level(av_sync_ms, 450, 900),
        },
    ]


def generate_ai_interrogation_coach(
    indicators: list[dict], question: str, consistency_index: float
) -> dict:
    """Generate smart AI Interrogation Coach follow-up tests (Reverse Chronological + Unexpected Detail)."""
    elevated = [ind for ind in indicators if ind["status"] in ("high", "elevated")]
    top_names = [ind["name"] for ind in elevated[:3]]
    q_clean = question.strip() or "is ghatna"

    reverse_prompt = (
        f"Reverse Order Test: '{q_clean}' ke baare mein poori baat ulte order (aakhiri pal se shuruat tak) mein bina ruke sunao."
    )
    detail_prompt = (
        "Unexpected Detail Shift: Us waqt aas-paas kaunse rang ke kapde, awaaz, ya kaunsa vyakti sabse paas tha? Exact 5 second mein batao."
    )
    targeted = []
    for ind in elevated[:3]:
        if ind["id"] in (1, 4):
            targeted.append("Camera mein seedha aankh mila kar bina nazar hataye yahi baat dobara kaho.")
        elif ind["id"] in (9, 14, 19):
            targeted.append("Aapki pulse aur saans is sawaal par tez hui — kya koi aisi detail hai jo aap bolne se ruk rahe hain?")
        elif ind["id"] in (15, 16, 17, 20):
            targeted.append("Jawab dene se pehle hesitation aur voice tremor aaya — bina 'shayad' bole seedha Haan ya Na mein jawab dein.")

    if not targeted:
        targeted.append("Baseline ke hisaab se response kaafi steady tha — ek confirmation detail poochh kar verify karein.")

    return {
        "cognitive_load_level": "HIGH" if consistency_index < 45 else "MODERATE" if consistency_index < 72 else "LOW",
        "top_stress_channels": top_names,
        "reverse_chronological_test": reverse_prompt,
        "unexpected_detail_shift": detail_prompt,
        "targeted_prompts": targeted[:3],
    }


def compute_truth_score(
    video_metrics: dict,
    audio_metrics: dict,
    baseline_video: dict | None = None,
    baseline_audio: dict | None = None,
    question: str = "",
    weights: dict | None = None,
) -> dict:
    """Unified 21-point multimodal video+audio scoring, media authenticity, and AI Interrogation Coach."""
    w = weights or {"visual": 0.45, "acoustic": 0.45, "cognitive": 0.10}
    visual_stress = float(video_metrics.get("visual_stress_index", 0.0))
    vocal_stress = float(audio_metrics.get("vocal_stress_index", 0.0))
    audio_available = bool(audio_metrics.get("audio_available", False))

    # Baseline calibration delta adjustment if Stage 1 baseline was provided
    delta_penalty = 0.0
    if baseline_video:
        bpm_jump = max(0.0, float(video_metrics.get("rppg_bpm", 74.0)) - float(baseline_video.get("rppg_bpm", 74.0)))
        blink_jump = abs(float(video_metrics.get("blink_rate_per_min", 16.0)) - float(baseline_video.get("blink_rate_per_min", 16.0)))
        delta_penalty += min(18.0, bpm_jump * 0.7 + blink_jump * 0.4)
    if baseline_audio and audio_available:
        lat_jump = max(0.0, float(audio_metrics.get("response_latency_ms", 0.0)) - float(baseline_audio.get("response_latency_ms", 0.0)))
        delta_penalty += min(12.0, lat_jump / 200.0)

    cognitive_load = min(100.0, float(audio_metrics.get("response_latency_ms", 0.0)) / 25.0 + delta_penalty * 2.0)

    if audio_available:
        combined_stress = round(
            min(
                100.0,
                w.get("visual", 0.45) * visual_stress
                + w.get("acoustic", 0.45) * vocal_stress
                + w.get("cognitive", 0.10) * cognitive_load
                + delta_penalty * 0.35,
            ),
            1,
        )
    else:
        combined_stress = round(min(100.0, visual_stress + delta_penalty * 0.4), 1)

    consistency_index = round(max(0.0, min(100.0, 100.0 - combined_stress)), 1)

    if consistency_index >= 72.0:
        classification = "Low Stress / Consistent"
        verdict_hi = "Ye bilkul sahi bol raha hai! Chehra aur awaaz bilkul natural aur steady hain."
    elif consistency_index >= 45.0:
        classification = "Moderate Cognitive Load"
        verdict_hi = "Dhyan dein! Jawab mein thoda hesitation aur confusion hai. Ek follow-up sawaal poochhein."
    else:
        classification = "Elevated Stress Indicators"
        verdict_hi = "Savdhaan! Ye jhoot bol raha hai ya kaafi zyada stress mein hai! Dobara pakke saboot ke saath poochhein."

    indicators_21 = build_21_point_indicators(video_metrics, audio_metrics, baseline_video, baseline_audio)
    coach = generate_ai_interrogation_coach(indicators_21, question, consistency_index)

    real_human = float(video_metrics.get("real_human_pct", 88.0))
    human_voice = float(audio_metrics.get("human_voice_pct", 90.0)) if audio_available else 85.0
    authenticity = {
        "real_human_pct": real_human,
        "deepfake_risk_pct": round(100.0 - real_human, 1),
        "human_voice_pct": human_voice,
        "voice_clone_risk_pct": round(100.0 - human_voice, 1),
        "overall_status": (
            "Authentic Live Human"
            if real_human >= 70.0 and human_voice >= 70.0
            else "Review Media Authenticity"
        ),
    }

    findings = []
    if baseline_video:
        findings.append(f"Stage-1 Baseline calibrated (rPPG {baseline_video.get('rppg_bpm', 72)} BPM → Target {video_metrics.get('rppg_bpm', 74)} BPM).")
    if video_metrics.get("face_detected_ratio", 0.0) < 40.0:
        findings.append("Low frontal face visibility reduced visual tracking confidence.")
    if video_metrics.get("motion_jitter_index", 0.0) > 55.0:
        findings.append("Elevated head or upper-body micro-movement variance detected.")
    if video_metrics.get("blink_rate_per_min", 0.0) > 28.0:
        findings.append("Above-baseline blink frequency observed during speech segments.")
    if audio_available and audio_metrics.get("voice_micro_tremor_index", 0.0) > 45.0:
        findings.append("8-12 Hz vocal cord micro-tremor spike detected in acoustic spectrum.")
    if audio_available and audio_metrics.get("pause_ratio", 0.0) > 42.0:
        findings.append("Frequent hesitation or silence intervals detected in audio track.")

    if not findings:
        findings.append("Vocal cadence, ocular patterns, and rPPG pulse remained within steady baseline ranges.")

    return {
        "consistency_index": consistency_index,
        "combined_stress_index": combined_stress,
        "classification": classification,
        "verdict_hi": verdict_hi,
        "confidence": "High" if video_metrics.get("face_detected_ratio", 0.0) >= 60.0 and audio_available else "Moderate",
        "calibrated": bool(baseline_video),
        "video": video_metrics,
        "audio": audio_metrics,
        "indicators_21": indicators_21,
        "authenticity": authenticity,
        "interrogation_coach": coach,
        "findings": findings,
        "disclaimer": (
            "Consent-based forensic signal analysis measures physiological, acoustic, and visual stress indicators only "
            "and does not constitute legal or definitive lie verification."
        ),
    }
