import math
from types import SimpleNamespace

from app.moderation import check_unsafe
from app.nlp import detect_contradictions
from app.scoring import build_baseline, confidence_label, score_window

BASELINE = build_baseline(
    [
        {"blink_rate": 14.0, "gaze_off_ratio": 0.10, "pitch_std": 12.0, "detail_score": 9.0, "hedge_rate": 2.0},
        {"blink_rate": 16.0, "gaze_off_ratio": 0.12, "pitch_std": 14.0, "detail_score": 11.0, "hedge_rate": 3.0},
        {"blink_rate": 15.0, "gaze_off_ratio": 0.09, "pitch_std": 11.0, "detail_score": 10.0, "hedge_rate": 2.5},
    ]
)


def test_unsafe_moderation():
    assert "bomb" in check_unsafe("Bomb kaha rakha hai?")
    assert "gun" in check_unsafe("Tumhare paas gun kaha hai?")
    assert check_unsafe("Tum kal office kitne baje gaye the?") == []


def test_stressed_window_triggers_verdict():
    stressed = {
        "blink_rate": 44.0,
        "gaze_off_ratio": 0.48,
        "pitch_std": 34.0,
        "detail_score": 0.0,
        "hedge_rate": 28.0,
        "bpm_delta": 18.0,
        "response_latency": 5.2,
    }
    score, _, signals, verdict, followup, radar = score_window(stressed, BASELINE, coverage=0.9, window_count=10)
    assert score is not None and score > 62
    assert signals and "kyunki" in verdict.lower()
    assert followup is not None
    assert radar["bio"] > 50


def test_contradiction_detector():
    wins = [
        SimpleNamespace(t=10.0, question_idx=0, transcript="Main 5 baje ghar gaya tha"),
        SimpleNamespace(t=16.0, question_idx=0, transcript="Nahi matlab 8 baje pahuncha tha"),
    ]
    found = detect_contradictions(wins)
    assert len(found) == 1 and found[0]["type"] == "time_shift"


def test_confidence_and_sigmoid():
    from app.scoring import _sigmoid
    assert confidence_label(80, 0.9) == "HIGH"
    assert math.isclose(_sigmoid(0), 0.5)


def test_21_point_multimodal_scoring_and_coach():
    from app.scoring import compute_truth_score

    baseline_v = {"rppg_bpm": 72.0, "blink_rate_per_min": 15.0, "visual_stress_index": 20.0}
    baseline_a = {"response_latency_ms": 300.0, "vocal_stress_index": 22.0, "audio_available": True}
    target_v = {
        "face_detected_ratio": 90.0,
        "blink_rate_per_min": 34.0,
        "blink_duration_ms": 310.0,
        "pupil_dilation_ratio": 36.0,
        "gaze_instability_index": 58.0,
        "gaze_aversion_direction": "Upper-Right",
        "lip_compression_index": 55.0,
        "eyebrow_asymmetry_index": 42.0,
        "nostril_flare_index": 44.0,
        "duping_delight_flashes": 3,
        "rppg_bpm": 91.0,
        "head_jitter_index": 52.0,
        "postural_freeze_index": 30.0,
        "shoulder_shrug_asymmetry": 40.0,
        "hand_to_face_adaptors_pct": 25.0,
        "swallowing_larynx_spikes": 3,
        "motion_jitter_index": 60.0,
        "first_expression_sec": 0.9,
        "real_human_pct": 92.0,
        "visual_stress_index": 68.0,
    }
    target_a = {
        "audio_available": True,
        "response_latency_ms": 1450.0,
        "voice_micro_tremor_index": 56.0,
        "pitch_jitter_pct": 6.2,
        "amplitude_shimmer_pct": 7.1,
        "formant_center_hz": 1240.0,
        "formant_shift_index": 48.0,
        "sharp_inhalations": 3,
        "breathing_irregularity": 52.0,
        "speech_rate_wps": 3.4,
        "speech_rate_variance": 55.0,
        "first_speech_sec": 0.2,
        "pause_ratio": 48.0,
        "linguistic": {"pronoun_rate_pct": 1.2, "pronoun_avoidance_flag": True},
        "human_voice_pct": 94.0,
        "vocal_stress_index": 66.0,
    }

    report = compute_truth_score(
        target_v,
        target_a,
        baseline_video=baseline_v,
        baseline_audio=baseline_a,
        question="Kya aap kal raat wahan gaye the?",
    )
    assert report["calibrated"] is True
    assert len(report["indicators_21"]) == 21
    assert report["authenticity"]["real_human_pct"] == 92.0
    assert report["authenticity"]["human_voice_pct"] == 94.0
    assert "Reverse Order Test" in report["interrogation_coach"]["reverse_chronological_test"]
    assert report["verdict_hi"]

