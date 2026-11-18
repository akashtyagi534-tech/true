def compute_truth_score(video_metrics: dict, audio_metrics: dict) -> dict:
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
    elif consistency_index >= 45.0:
        classification = "Moderate Cognitive Load"
    else:
        classification = "Elevated Stress Indicators"

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
        "confidence": "High" if video_metrics.get("face_detected_ratio", 0.0) >= 60.0 and audio_available else "Moderate",
        "video": video_metrics,
        "audio": audio_metrics,
        "findings": findings,
        "disclaimer": (
            "Signal analysis measures acoustic and visual stress indicators only and "
            "does not constitute definitive truth or deception verification."
        ),
    }
