"""Evaluate a self-hosted speech server before enabling voice for a language.

STT: word error rate on recordings you provide (tests/voice/<lang>/*.wav + matching .txt transcript).
TTS: synthesises the design copy's answers into tests/voice/out/<lang>/ for NATIVE-SPEAKER listening.

    VOICE_BASE_URL=http://localhost:8000/v1 STT_PROVIDER=openai_compat_http TTS_PROVIDER=openai_compat_http \\
      TTS_MODEL=<model> python scripts/eval_voice.py --lang pcm

Only add a language to VOICE_APPROVED_LANGS if WER is acceptable (suggested < 0.25) AND listeners
(young women aged 15–24 who speak the language) rate the audio understandable. Never ship garbled audio.
"""
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from app.config import get_settings  # noqa: E402
from app.copy_store import CopyStore  # noqa: E402
from app.voice.base import HttpVoice  # noqa: E402


def wer(ref: str, hyp: str) -> float:
    r, h = ref.lower().split(), hyp.lower().split()
    d = [[0] * (len(h) + 1) for _ in range(len(r) + 1)]
    for i in range(len(r) + 1):
        d[i][0] = i
    for j in range(len(h) + 1):
        d[0][j] = j
    for i in range(1, len(r) + 1):
        for j in range(1, len(h) + 1):
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (r[i - 1] != h[j - 1]))
    return d[-1][-1] / max(len(r), 1)


ap = argparse.ArgumentParser()
ap.add_argument("--lang", required=True, choices=["en", "pcm", "ha"])
a = ap.parse_args()
s = get_settings()
v = HttpVoice(s.voice_base_url, s.voice_api_key, s.stt_model, s.tts_model, True, True)
clips = sorted((ROOT / "tests" / "voice" / a.lang).glob("*.wav"))
if clips:
    scores = []
    for wav in clips:
        ref = wav.with_suffix(".txt").read_text().strip()
        hyp = v.transcribe(wav.read_bytes(), "audio/wav", a.lang) or ""
        scores.append(wer(ref, hyp))
        print(f"{wav.name}: WER {scores[-1]:.2f}  | {hyp}")
    print(f"mean WER {sum(scores) / len(scores):.2f} over {len(scores)} clips")
else:
    print(f"No STT test clips in tests/voice/{a.lang}/ (add .wav + .txt pairs recorded with consent by adult volunteers).")
copy = CopyStore(ROOT / "content")
out = ROOT / "tests" / "voice" / "out" / a.lang
out.mkdir(parents=True, exist_ok=True)
for key in ("answer_kiss", "protect", "unknown"):
    audio = v.synthesize(copy.t(("qa", key), a.lang), a.lang)
    if audio:
        (out / f"{key}.mp3").write_bytes(audio)
        print(f"wrote {out / (key + '.mp3')} for listening")
    else:
        print(f"TTS returned nothing for {key}")
