"""Crop the revised ThriftLine mark off its paper background.

Outputs:
- assets/images/thriftline-logo.png — rounded tile, transparent outside
- assets/images/thriftline-app-icon.png — full-bleed opaque teal canvas
"""

from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/images/thriftline_revised_app_logo.jpg"
LOGO_OUT = ROOT / "assets/images/thriftline-logo.png"
ICON_OUT = ROOT / "assets/images/thriftline-app-icon.png"


def is_paper(r: int, g: int, b: int) -> bool:
    """Outer JPEG paper and its anti-aliased fringe, not the inner white mark."""
    luma = (r + g + b) / 3
    # Solid teal is ~77 luma; fringe mixes paper with teal up to ~180.
    return luma >= 138


def content_bbox(im: Image.Image) -> tuple[int, int, int, int]:
    w, h = im.size
    px = im.load()
    min_x, min_y, max_x, max_y = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y][:3]
            if not is_paper(r, g, b):
                if x < min_x:
                    min_x = x
                if y < min_y:
                    min_y = y
                if x > max_x:
                    max_x = x
                if y > max_y:
                    max_y = y
    return min_x, min_y, max_x + 1, max_y + 1


def square_bbox(left: int, top: int, right: int, bottom: int) -> tuple[int, int, int, int]:
    width = right - left
    height = bottom - top
    side = min(width, height)
    extra_x = width - side
    extra_y = height - side
    left += extra_x // 2
    right = left + side
    top += extra_y // 2
    bottom = top + side
    return left, top, right, bottom


def flood_outer_mask(rgb: Image.Image) -> Image.Image:
    """True (255) for paper connected to the crop border; False for the mark."""
    w, h = rgb.size
    px = rgb.load()
    visited = [[False] * w for _ in range(h)]
    stack: list[tuple[int, int]] = []

    def maybe_push(x: int, y: int) -> None:
        if 0 <= x < w and 0 <= y < h and not visited[y][x]:
            r, g, b = px[x, y]
            if is_paper(r, g, b):
                visited[y][x] = True
                stack.append((x, y))

    for x in range(w):
        maybe_push(x, 0)
        maybe_push(x, h - 1)
    for y in range(h):
        maybe_push(0, y)
        maybe_push(w - 1, y)

    while stack:
        x, y = stack.pop()
        maybe_push(x + 1, y)
        maybe_push(x - 1, y)
        maybe_push(x, y + 1)
        maybe_push(x, y - 1)

    mask = Image.new("L", (w, h), 0)
    mp = mask.load()
    for y in range(h):
        for x in range(w):
            if visited[y][x]:
                mp[x, y] = 255
    # Expand slightly so JPEG fringe around the rounded tile disappears.
    return mask.filter(ImageFilter.MaxFilter(size=3)).filter(
        ImageFilter.GaussianBlur(radius=0.45)
    )


def dominant_teal(rgb: Image.Image, outer: Image.Image) -> tuple[int, int, int]:
    px = rgb.load()
    op = outer.load()
    w, h = rgb.size
    buckets: dict[tuple[int, int, int], int] = {}
    for y in range(h):
        for x in range(w):
            if op[x, y] > 8:
                continue
            r, g, b = px[x, y]
            if r < 80 and 70 < g < 150 and 60 < b < 140:
                key = (r, g, b)
                buckets[key] = buckets.get(key, 0) + 1
    if not buckets:
        return (24, 107, 99)
    return max(buckets.items(), key=lambda item: item[1])[0]


def main() -> None:
    src = Image.open(SRC).convert("RGB")
    left, top, right, bottom = square_bbox(*content_bbox(src))
    tile = src.crop((left, top, right, bottom))
    outer = flood_outer_mask(tile)
    teal = dominant_teal(tile, outer)

    rgba = tile.convert("RGBA")
    tp = tile.load()
    rp = rgba.load()
    op = outer.load()
    w, h = tile.size
    for y in range(h):
        for x in range(w):
            alpha = 255 - op[x, y]
            r, g, b = tp[x, y]
            if alpha < 255:
                rp[x, y] = (r, g, b, alpha)
            else:
                rp[x, y] = (r, g, b, 255)

    # High-res splash mark keeps the rounded tile without paper white.
    logo = rgba.resize((1024, 1024), Image.Resampling.LANCZOS)
    logo.save(LOGO_OUT, "PNG", optimize=True)

    # Launcher icon must be opaque; fill outer paper with brand teal so
    # system masks never reveal a white frame.
    icon = Image.new("RGB", (w, h), teal)
    icon.paste(rgba, mask=rgba.split()[3])
    icon = icon.resize((1024, 1024), Image.Resampling.LANCZOS)
    icon.save(ICON_OUT, "PNG", optimize=True)

    print("crop", left, top, right, bottom, "side", right - left)
    print("teal", teal)
    print("wrote", LOGO_OUT, logo.size, logo.mode)
    print("wrote", ICON_OUT, icon.size, icon.mode)


if __name__ == "__main__":
    main()
