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


def compute_truth_score(video_metrics: dict, audio_metrics: dict) -> dict:
    """Mobile APK /analyze multimodal video+audio scoring."""
    visual_stress = float(video_metrics.get("visual_stress_index", 0.0))
    vocal_stress = float(audio_metrics.get("vocal_stress_index", 0.0))
    audio_available = bool(audio_metrics.get("audio_available", False))

    if audio_available:
        combined_stress = round((0.45 * visual_stress) + (0.55 * vocal_stress), 1)
    else:
        combined_stress = round(visual_stress, 1)

    consistency_index = round(max(0.0, min(100.0, 100.0 - combined_stress)), 1)

    if consistency_index >= 72.0:
        classification = "Low Stress / Consistent"
        verdict_hi = "Ye jawab natural aur sahi lag raha hai — chehra aur awaaz steady hain."
    elif consistency_index >= 45.0:
        classification = "Moderate Cognitive Load"
        verdict_hi = "Thoda hesitation ya confusion lag raha hai — ek follow-up sawaal poochna theek rahega."
    else:
        classification = "Elevated Stress Indicators"
        verdict_hi = "Dhyan do, yahan kaafi stress spike mila hai — dobara exact details ke saath poochho."

    findings = []
    if video_metrics.get("face_detected_ratio", 0.0) < 40.0:
        findings.append("Low frontal face visibility reduced visual tracking confidence.")
    if video_metrics.get("motion_jitter_index", 0.0) > 55.0:
        findings.append("Elevated head or upper-body micro-movement variance detected.")
    if video_metrics.get("blink_rate_per_min", 0.0) > 28.0:
        findings.append("Above-baseline blink frequency observed during speech segments.")
    if audio_available and audio_metrics.get("pitch_std_hz", 0.0) > 38.0:
        findings.append("Notable fundamental frequency (F0) pitch variance across utterances.")
    if audio_available and audio_metrics.get("pause_ratio", 0.0) > 42.0:
        findings.append("Frequent hesitation or silence intervals detected in audio track.")

    if not findings:
        findings.append("Vocal cadence and visual movement remained within steady baseline ranges.")

    return {
        "consistency_index": consistency_index,
        "combined_stress_index": combined_stress,
        "classification": classification,
        "verdict_hi": verdict_hi,
        "confidence": "High" if video_metrics.get("face_detected_ratio", 0.0) >= 60.0 and audio_available else "Moderate",
        "video": video_metrics,
        "audio": audio_metrics,
        "findings": findings,
        "disclaimer": (
            "Signal analysis measures acoustic and visual stress indicators only and "
            "does not constitute definitive truth or deception verification."
        ),
    }
