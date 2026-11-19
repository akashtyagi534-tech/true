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
