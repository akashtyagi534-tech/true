import re

UNSAFE_PATTERNS = [
    r"\bbomb\b", r"\bbam\b", r"\bboom\b", r"\bblast\b", r"\bexplosive\b", r"\brdx\b",
    r"\bgun\b", r"\bpistol\b", r"\brifle\b", r"\bkatta\b", r"\bbandook\b", r"\bweapon\b",
    r"\bterror\b", r"\bterrorist\b", r"\batankwadi\b", r"\battack\b", r"\bhamla\b",
    r"\bkill\b", r"\bmurder\b", r"\bmaar\s+dala\b", r"\bhatya\b", r"\bchaku\b",
    r"\bdrugs?\b", r"\bganja\b", r"\bcharas\b", r"\bsmack\b", r"\bcocaine\b",
    r"\bkidnap\b", r"\bapharan\b", r"\bsuicide\b", r"\bpoison\b", r"\bzeher\b",
]

COMPILED = [(pat, re.compile(pat, re.IGNORECASE)) for pat in UNSAFE_PATTERNS]


def check_unsafe(text: str) -> list[str]:
    if not text:
        return []
    matches: list[str] = []
    for _, rx in COMPILED:
        m = rx.search(text)
        if m:
            matches.append(m.group(0).lower())
    return sorted(set(matches))
