"""Question-box hygiene: strip names, phone numbers, emails and handles before storage,
and filter prank/abusive submissions. Deliberately over-redacts: a lost word is
better than an identified student."""
from __future__ import annotations

import re

PHONE = re.compile(r"\+?\d[\d\s\-().]{5,}\d")
EMAIL = re.compile(r"\b[\w.+-]+@[\w-]+\.[\w.-]+\b")
HANDLE = re.compile(r"(?<!\w)@\w{2,}")
URL = re.compile(r"https?://\S+|www\.\S+", re.I)
NAME_INTRO = re.compile(
    r"\b(my name is|my names are|i am called|call me|i'?m called|na me be|my name na|this is|it's me|name:)\s+([A-Za-z][\w'-]*)((?-i:\s+[A-Z][\w'-]*))?",
    re.I)
# Possessive or relationship + capitalised word: "Amaka's boyfriend", "my friend Tunde", "Mr Bello"
NAME_REL = re.compile(r"\b(my\s+(friend|boyfriend|girlfriend|sister|brother|classmate|teacher|cousin|neighbour|neighbor|aunty|uncle|mate)|"
                      r"mr\.?|mrs\.?|miss|ms\.?|aunty|uncle|teacher|sir|ma)\s+([A-Z][\w'-]+)")
# Capitalised words that are NOT names and should survive redaction.
KEEP = {"HIV", "AIDS", "PrEP", "PEP", "STI", "STIs", "STD", "ART", "ARV", "HPV", "I", "I'm", "I've", "I'd", "OK",
        "Lagos", "Kano", "Abuja", "Nigeria", "God", "WHO", "Can", "Is", "Do", "Does", "What", "How", "Why", "When",
        "Where", "Who", "Which", "If", "My", "Please", "Abeg", "Wetin", "Na", "E", "Una", "Pls", "And", "But", "Or",
        "Should", "Will", "Would", "Could", "Are", "Am", "The", "A", "An", "Yes", "No", "Hi", "Hello", "Sir", "Ma",
        "Truvada", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday", "Mr", "Mrs", "Miss"}

ABUSE = [re.compile(p, re.I) for p in [
    r"\b(fuck|fucking|shit|bitch|bastard|cunt|dick|pussy|whore|slut|ashawo|mumu|ode|olodo|werey|ewu|oloshi)\b",
    r"\b(sex(y)?\s+teacher|teacher\s+is\s+(gay|a\s+(slut|whore)))\b",
    r"\b(nude|nudes|porn|send\s+pics?)\b",
    r"(.)\1{7,}",                     # keyboard mashing: aaaaaaaa
    r"^\W*\w?\W*$",                    # empty-ish
    r"\b(lol|lmao|hahaha+)\b.*\b(lol|lmao|hahaha+)\b",
]]


def redact(text: str) -> tuple[str, bool]:
    """Return (redacted_text, changed)."""
    t0 = text
    t = URL.sub("[link]", text)
    t = EMAIL.sub("[email]", t)
    t = PHONE.sub("[number]", t)
    t = HANDLE.sub("[handle]", t)
    t = NAME_INTRO.sub(lambda m: m.group(1) + " [name]", t)
    t = NAME_REL.sub(lambda m: m.group(1) + " [name]", t)
    # Any remaining capitalised word that is not sentence-initial and not a known keep-word.
    out = []
    for i, tok in enumerate(re.split(r"(\s+)", t)):
        word = re.sub(r"[^\w'-]", "", tok)
        prev = "".join(out).rstrip()
        sentence_start = not prev or prev[-1] in ".?!:\n"
        if word and word[0].isupper() and not sentence_start and word not in KEEP and not word.isupper() \
                and not word.startswith("[") and word.split("'")[0] not in KEEP:
            tok = tok.replace(word, "[name]")
        out.append(tok)
    t = "".join(out)
    return t, t != t0


def is_abusive(text: str) -> bool:
    return any(p.search(text) for p in ABUSE)
