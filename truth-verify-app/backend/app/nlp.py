import re

HEDGES = {
    "shayad", "lagta", "lagtaa", "matlab", "actually", "maybe", "probably",
    "think", "guess", "kaafi", "thoda", "almost", "types", "sort", "somewhat",
    "possibly", "roughly", "around", "approximately", "pakka", "yaad", "confuse",
    "maloom", "hoga", "hogi", "sakta", "sakti",
}

PHRASE_HEDGES = [
    "i mean", "you know", "pata nahi", "yaad nahi", "pakka nahi",
    "sach bolu", "kasam se", "believe me", "trust me", "to be honest", "honestly",
]

FILLERS = {
    "uhh", "uh", "umm", "um", "hmm", "err", "aaa", "eee", "like", "basically", "arre", "woh", "wo"
}

DISTANCING = {
    "woh", "usne", "unhone", "banda", "log", "they", "someone", "kisi", "koi"
}

DETAIL_MARKERS = re.compile(r"\b\d+(?::\d+)?\b")
TIME_MARKERS = re.compile(r"\b(\d{1,2})\s*(?:baje|am|pm|o'clock|hours?|min|minute)\b", re.IGNORECASE)


def tokenise(text: str) -> list[str]:
    return re.findall(r"[a-zA-Z\u0900-\u097F]+", (text or "").lower())


def hedge_rate(text: str) -> float:
    low = (text or "").lower()
    tokens = tokenise(low)
    if not tokens:
        return 0.0
    hits = sum(1 for tok in tokens if tok in HEDGES)
    phrase_hits = sum(1 for p in PHRASE_HEDGES if p in low)
    return (hits + phrase_hits * 1.5) / len(tokens) * 100


def filler_rate(text: str) -> float:
    tokens = tokenise(text)
    if not tokens:
        return 0.0
    hits = sum(1 for tok in tokens if tok in FILLERS)
    return hits / len(tokens) * 100


def distancing_rate(text: str) -> float:
    tokens = tokenise(text)
    if not tokens:
        return 0.0
    hits = sum(1 for tok in tokens if tok in DISTANCING)
    return hits / len(tokens) * 100


def detail_score(text: str) -> float:
    tokens = tokenise(text)
    if not tokens:
        return 0.0
    numbers = len(DETAIL_MARKERS.findall(text or ""))
    proper = sum(1 for word in (text or "").split() if word[:1].isupper())
    return (numbers * 2 + proper) / len(tokens) * 100


def speech_rate(text: str, seconds: float) -> float:
    tokens = tokenise(text)
    if seconds <= 0:
        return 0.0
    return len(tokens) / seconds


def enrich(text: str, seconds: float, pause_ratio: float) -> dict:
    return {
        "hedge_rate": round(hedge_rate(text), 4),
        "filler_rate": round(filler_rate(text), 4),
        "distancing_rate": round(distancing_rate(text), 4),
        "detail_score": round(detail_score(text), 4),
        "speech_rate": round(speech_rate(text, seconds), 4),
        "pause_ratio": round(pause_ratio, 4),
        "word_count": len(tokenise(text)),
    }


def detect_contradictions(windows: list) -> list[dict]:
    findings: list[dict] = []
    seen_times: list[tuple[float, str, int]] = []
    denial_phrases = ("nahi gaya", "nahi tha", "nahi ki", "never went", "didn't do", "kabhi nahi")
    confirm_phrases = ("gaya tha", "kiya tha", "milne gaya", "haan main", "yes i")

    q_stance: dict[int, tuple[float, str]] = {}

    for w in windows:
        txt = (w.transcript or "").strip()
        if not txt:
            continue
        low = txt.lower()

        for m in TIME_MARKERS.finditer(low):
            val = m.group(0)
            for prev_t, prev_val, prev_q in seen_times:
                if prev_q == w.question_idx and prev_val != val:
                    findings.append({
                        "type": "time_shift",
                        "message": f"Ek hi sawaal mein time badla gaya: pehle '{prev_val}' bola, baad mein '{val}'.",
                        "t_first": round(prev_t, 1),
                        "t_second": round(w.t, 1),
                    })
                    break
            seen_times.append((w.t, val, w.question_idx))

        has_deny = any(p in low for p in denial_phrases)
        has_conf = any(p in low for p in confirm_phrases)
        if has_deny or has_conf:
            stance = "deny" if has_deny else "confirm"
            if w.question_idx in q_stance and q_stance[w.question_idx][1] != stance:
                findings.append({
                    "type": "stance_flip",
                    "message": "Jawab ka stance palta: pehle haan/confirm kiya, phir inkaar (ya ulta).",
                    "t_first": round(q_stance[w.question_idx][0], 1),
                    "t_second": round(w.t, 1),
                })
            else:
                q_stance[w.question_idx] = (w.t, stance)

    unique = []
    seen_keys = set()
    for f in findings:
        key = (f["type"], f["t_second"])
        if key not in seen_keys:
            seen_keys.add(key)
            unique.append(f)
    return unique[:10]
