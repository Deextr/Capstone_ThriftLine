"""Build white-on-transparent ic_stat_thriftline from assets/images/thriftline-app-icon.png."""
from __future__ import annotations

import os
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "images" / "thriftline-app-icon.png"
OUT_BASE = ROOT / "android" / "app" / "src" / "main" / "res"
SIZES = {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}


def main() -> None:
    img = Image.open(SRC).convert("RGBA")
    px = img.load()
    w, h = img.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    opx = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 32:
                continue
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            if lum > 210:
                opx[x, y] = (255, 255, 255, 255)

    for dpi, size in SIZES.items():
        folder = OUT_BASE / f"drawable-{dpi}"
        folder.mkdir(parents=True, exist_ok=True)
        out.resize((size, size), Image.Resampling.LANCZOS).save(
            folder / "ic_stat_thriftline.png"
        )
    drawable = OUT_BASE / "drawable"
    drawable.mkdir(parents=True, exist_ok=True)
    out.resize((24, 24), Image.Resampling.LANCZOS).save(
        drawable / "ic_stat_thriftline.png"
    )
    print("Wrote ic_stat_thriftline.png to res/drawable*")


if __name__ == "__main__":
    main()
