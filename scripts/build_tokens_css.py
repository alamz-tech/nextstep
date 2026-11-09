"""Generate app/static/shared/tokens.css from content/tokens.json (the design source of truth)."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
t = json.loads((ROOT / "content" / "tokens.json").read_text())


def block(d):
    return "\n".join(f"  --ns-color-{k}: {v};" for k, v in d.items())


light, dark = t["color"]["light"], dict(t["color"]["dark"])
# dark set in tokens.json has no tint for support/accent-soft; fall back to the light values
for k in light:
    dark.setdefault(k, light[k])
other = []
for k, v in t["space"].items():
    other.append(f"  --ns-space-{k}: {v}px;")
for k, v in t["radius"].items():
    if k != "bubble":
        other.append(f"  --ns-radius-{k}: {v}px;")
for k in ("display", "body", "mono"):
    other.append(f"  --ns-font-{k}: {t['font'][k]};")
for k, v in t["size"].items():
    other.append(f"  --ns-size-{k}: {v}px;")
css = f"""/* Generated from content/tokens.json by scripts/build_tokens_css.py. Do not edit by hand. */
@import url("/static/fonts/fonts.css");
:root {{
{block(light)}
{chr(10).join(other)}
  color-scheme: light;
}}
@media (prefers-color-scheme: dark) {{
  :root:not([data-theme="light"]) {{
{block(dark)}
    color-scheme: dark;
  }}
}}
:root[data-theme="dark"] {{
{block(dark)}
  color-scheme: dark;
}}
"""
out = ROOT / "app" / "static" / "shared" / "tokens.css"
out.write_text(css)
print("wrote", out)
