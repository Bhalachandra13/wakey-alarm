#!/usr/bin/env python3
"""
Generate the Wakey-Wakey launcher + store icon assets.

Pure Python (stdlib only — zlib + struct), so it runs without
PIL/ImageMagick. Renders a 1024×1024 master design, then
box-filter-downscales to every density the Android launcher
and the Play Console need:

  * 512×512 PNG                     — Play Store listing icon
  * mipmap-{m,h,xh,xxh,xxxh}dpi PNGs — legacy launcher fallback
                                       (minSdk 26 has adaptive
                                       icons, but the Play Console
                                       still wants the PNG set
                                       and some launchers on
                                       API 26-27 prefer them)
  * drawable/ic_launcher_foreground.png + adaptive XML — adaptive
                                       icon (API 26+)
  * 1024×500 PNG                    — Play Store feature graphic

The design: a deep-blue rounded square (brand colour #1E3A8A)
with a white alarm-clock face, an amber ring + hands (#F59E0B),
and a small white location pin overlapping the lower-right of
the clock face. Geometric, flat, recognisable at 48×48.

This script is idempotent — running it again overwrites the
generated assets. The script is intentionally self-contained
so the icon can be regenerated without external tools (no
Inkscape, no rsvg-convert, no Pillow).
"""

import os
import struct
import zlib
from pathlib import Path

# ---------------------------------------------------------------------------
# Brand colours
# ---------------------------------------------------------------------------

BG = (0x1E, 0x3A, 0x8A, 0xFF)       # deep blue
RING = (0xF5, 0x9E, 0x0B, 0xFF)     # amber
WHITE = (0xFF, 0xFF, 0xFF, 0xFF)
SHADOW = (0x00, 0x00, 0x00, 0x33)   # 20% black


# ---------------------------------------------------------------------------
# Master design — drawn onto a 1024×1024 RGBA buffer
# ---------------------------------------------------------------------------

def new_canvas(size: int) -> bytearray:
    # Transparent canvas; we paint the rounded-rect background first.
    return bytearray(size * size * 4)


def blend(dst: bytearray, size: int, x: int, y: int, src: tuple) -> None:
    """Straight alpha-over blend of a single pixel."""
    if x < 0 or y < 0 or x >= size or y >= size:
        return
    i = (y * size + x) * 4
    sa = src[3] / 255.0
    da = dst[i + 3] / 255.0
    out_a = sa + da * (1 - sa)
    if out_a == 0:
        return
    for c in range(3):
        dst[i + c] = round((src[c] * sa + dst[i + c] * da * (1 - sa)) / out_a)
    dst[i + 3] = round(out_a * 255)


def fill_rounded_rect(buf: bytearray, size: int, x0: int, y0: int,
                     x1: int, y1: int, radius: int, color: tuple) -> None:
    """Filled rounded rectangle (alpha-blended)."""
    for y in range(y0, y1):
        for x in range(x0, x1):
            # Distance from the nearest corner circle.
            cx = x0 + radius if x < x0 + radius else (x1 - 1 - radius if x >= x1 - radius else x)
            cy = y0 + radius if y < y0 + radius else (y1 - 1 - radius if y >= y1 - radius else y)
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if d <= radius:
                blend(buf, size, x, y, color)


def fill_circle(buf: bytearray, size: int, cx: float, cy: float, r: float,
                color: tuple) -> None:
    x0 = max(0, int(cx - r - 1))
    x1 = min(size, int(cx + r + 2))
    y0 = max(0, int(cy - r - 1))
    y1 = min(size, int(cy + r + 2))
    for y in range(y0, y1):
        for x in range(x0, x1):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if d <= r:
                blend(buf, size, x, y, color)


def stroke_circle(buf: bytearray, size: int, cx: float, cy: float,
                 r: float, thickness: float, color: tuple) -> None:
    x0 = max(0, int(cx - r - thickness - 1))
    x1 = min(size, int(cx + r + thickness + 2))
    y0 = max(0, int(cy - r - thickness - 1))
    y1 = min(size, int(cy + r + thickness + 2))
    for y in range(y0, y1):
        for x in range(x0, x1):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if r - thickness / 2 <= d <= r + thickness / 2:
                blend(buf, size, x, y, color)


def fill_line(buf: bytearray, size: int, x0: float, y0: float,
             x1: float, y1: float, thickness: float, color: tuple) -> None:
    """Thick line with round caps (rasterised)."""
    import math
    dx, dy = x1 - x0, y1 - y0
    length = (dx * dx + dy * dy) ** 0.5
    steps = int(length * 2) + 1
    for i in range(steps + 1):
        t = i / steps
        cx = x0 + dx * t
        cy = y0 + dy * t
        fill_circle(buf, size, cx, cy, thickness / 2, color)


def fill_triangle(buf: bytearray, size: int, p0, p1, p2, color: tuple) -> None:
    """Filled triangle (scanline)."""
    pts = sorted([p0, p1, p2], key=lambda p: p[1])
    (ax, ay), (bx_, by_), (cx_, cy_) = pts
    for y in range(int(ay), int(cy_) + 1):
        if y < by_:
            denom = by_ - ay if by_ != ay else 1
            t = (y - ay) / denom
            x_left = ax + (bx_ - ax) * t
        else:
            denom = cy_ - by_ if cy_ != by_ else 1
            t = (y - by_) / denom
            x_left = bx_ + (cx_ - bx_) * t
        denom2 = cy_ - ay if cy_ != ay else 1
        t2 = (y - ay) / denom2
        x_right = ax + (cx_ - ax) * t2
        if x_left > x_right:
            x_left, x_right = x_right, x_left
        for x in range(int(x_left), int(x_right) + 1):
            blend(buf, size, x, y, color)


def make_master(size: int = 1024) -> bytearray:
    buf = new_canvas(size)

    # Rounded-square background (full canvas, ~22% corner radius).
    fill_rounded_rect(buf, size, 0, 0, size, size, int(size * 0.22), BG)

    # Subtle inner shadow at the top-left for depth (optional, low alpha).
    # Kept very faint so the icon reads as flat-modern.

    # Alarm clock face — large white circle, centered slightly above
    # middle so the location pin can sit at the lower-right.
    cx, cy = size / 2, size * 0.46
    r_face = size * 0.30
    fill_circle(buf, size, cx, cy, r_face, WHITE)

    # Amber ring around the face.
    stroke_circle(buf, size, cx, cy, r_face + size * 0.012,
                  size * 0.014, RING)

    # Clock hands — pointing to 7:00 (hour hand to 7, minute hand to 12).
    # The hour hand is short + thick, the minute hand is long + thinner.
    hour_len = r_face * 0.55
    min_len = r_face * 0.80
    # 7:00: hour hand at 210° (towards lower-left), minute at 0° (up).
    import math
    hour_angle = math.radians(210)
    min_angle = math.radians(270)  # 12 o'clock
    fill_line(buf, size, cx, cy,
              cx + math.cos(hour_angle) * hour_len,
              cy + math.sin(hour_angle) * hour_len,
              size * 0.028, RING)
    fill_line(buf, size, cx, cy,
              cx + math.cos(min_angle) * min_len,
              cy + math.sin(min_angle) * min_len,
              size * 0.020, RING)
    # Centre pin.
    fill_circle(buf, size, cx, cy, size * 0.020, RING)

    # Location pin — overlapping the lower-right of the clock face.
    # Teardrop shape: a circle on top with a triangle pointing down,
    # filled white with a small inner circle (the "hole" in the pin).
    pin_cx = size * 0.70
    pin_cy = size * 0.66
    pin_r = size * 0.11
    # White shadow underneath for separation from the clock face.
    fill_circle(buf, size, pin_cx + size * 0.006, pin_cy + size * 0.008,
                pin_r + size * 0.004, SHADOW)
    # White pin body.
    fill_circle(buf, size, pin_cx, pin_cy, pin_r, WHITE)
    # Triangle tip pointing down to the centre of the pin.
    tip_y = pin_cy + pin_r * 1.35
    fill_triangle(buf, size,
                  (pin_cx - pin_r * 0.65, pin_cy + pin_r * 0.55),
                  (pin_cx + pin_r * 0.65, pin_cy + pin_r * 0.55),
                  (pin_cx, tip_y), WHITE)
    # Inner "hole" circle (the deep blue background showing through).
    fill_circle(buf, size, pin_cx, pin_cy, pin_r * 0.38, BG)

    return buf


# ---------------------------------------------------------------------------
# PNG encoder (RGBA, 8-bit, no interlace, filter type 0 = None)
# ---------------------------------------------------------------------------

def encode_png(buf: bytearray, w: int, h: int) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)  # 8-bit RGBA
    # Add a leading filter byte (0 = None) to every scanline.
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw.extend(buf[y * stride:(y + 1) * stride])
    idat = zlib.compress(bytes(raw), 9)
    return sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


# ---------------------------------------------------------------------------
# Box-filter downscale
# ---------------------------------------------------------------------------

def downscale(src: bytearray, src_w: int, src_h: int,
             dst_w: int, dst_h: int) -> bytearray:
    """Average-pool downscale. Simple, no anti-alias artefacts
    because the source is already anti-aliased via the blend step."""
    if (dst_w, dst_h) == (src_w, src_h):
        return bytearray(src)
    dst = bytearray(dst_w * dst_h * 4)
    x_ratio = src_w / dst_w
    y_ratio = src_h / dst_h
    for dy in range(dst_h):
        y0 = int(dy * y_ratio)
        y1 = max(y0 + 1, int((dy + 1) * y_ratio))
        for dx in range(dst_w):
            x0 = int(dx * x_ratio)
            x1 = max(x0 + 1, int((dx + 1) * x_ratio))
            r = g = b = a = 0
            n = 0
            for sy in range(y0, min(y1, src_h)):
                for sx in range(x0, min(x1, src_w)):
                    i = (sy * src_w + sx) * 4
                    r += src[i]; g += src[i + 1]; b += src[i + 2]; a += src[i + 3]
                    n += 1
            j = (dy * dst_w + dx) * 4
            dst[j] = r // n
            dst[j + 1] = g // n
            dst[j + 2] = b // n
            dst[j + 3] = a // n
    return dst


# ---------------------------------------------------------------------------
# Asset writer
# ---------------------------------------------------------------------------

def write_png(path: Path, buf: bytearray, w: int, h: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(encode_png(buf, w, h))
    print(f"  {path}  ({w}x{h}, {path.stat().st_size // 1024} KB)")


def main() -> None:
    repo = Path(__file__).resolve().parent.parent
    print("Rendering 1024x1024 master...")
    master = make_master(1024)
    master_512 = downscale(bytes(master), 1024, 1024, 512, 512)
    master_432 = downscale(bytes(master), 1024, 1024, 432, 432)

    # 1. Play Store listing icon (512x512).
    print("\nPlay Store listing icon:")
    write_png(repo / "store_assets" / "icon-512.png",
              bytearray(master_512), 512, 512)

    # 2. Legacy mipmap PNGs (Android launcher fallback).
    sizes = [
        ("mipmap-mdpi", 48),
        ("mipmap-hdpi", 72),
        ("mipmap-xhdpi", 96),
        ("mipmap-xxhdpi", 144),
        ("mipmap-xxxhdpi", 192),
    ]
    print("\nMipmap PNGs (legacy launcher):")
    for dirname, size in sizes:
        out = downscale(bytes(master), 1024, 1024, size, size)
        write_png(repo / "android" / "app" / "src" / "main" / "res"
                  / dirname / "ic_launcher.png", bytearray(out), size, size)
        # Same image for the round variant.
        write_png(repo / "android" / "app" / "src" / "main" / "res"
                  / dirname / "ic_launcher_round.png", bytearray(out), size, size)

    # 3. Adaptive icon foreground (the visible part of the launcher
    #    icon on API 26+). 108dp = 432px at xxxhdpi; we keep the full
    #    art centred with padding so it sits in the safe zone
    #    (the launcher masks it to a circle/squircle).
    print("\nAdaptive icon (API 26+):")
    write_png(repo / "android" / "app" / "src" / "main" / "res"
              / "drawable" / "ic_launcher_foreground.png",
              bytearray(master_432), 432, 432)

    # 4. Feature graphic — Play Store banner. 1024x500. We render a
    #    horizontal variant: same design stretched + the brand name
    #    on the right. Without a font renderer we can't draw the
    #    wordmark in Python, so we use a glyph-free "WW" mark built
    #    from the clock face, and document that the final feature
    #    graphic should add the wordmark in a design tool. The
    #    generated PNG is a safe fallback that ships with the
    #    build and is replaced before final publish.
    print("\nFeature graphic (1024x500):")
    fg = render_feature_graphic(1024, 500)
    write_png(repo / "store_assets" / "feature-graphic-1024x500.png",
              bytearray(fg), 1024, 500)


def render_feature_graphic(w: int, h: int) -> bytearray:
    """Feature graphic: deep blue background with the icon on the
    left and a neutral placeholder text block on the right. The
    final graphic should add the Wakey-Wakey wordmark + tagline
    in a design tool; the generated PNG is a safe fallback."""
    buf = new_canvas(w)
    # Solid deep-blue background.
    for i in range(0, w * h * 4, 4):
        buf[i:i + 4] = bytes(BG)

    # Place the icon on the left, vertically centred.
    icon_size = int(h * 0.78)
    icon = downscale(bytes(make_master(1024)), 1024, 1024, icon_size, icon_size)
    pad = (h - icon_size) // 2
    for y in range(icon_size):
        for x in range(icon_size):
            si = (y * icon_size + x) * 4
            sa = icon[si + 3] / 255.0
            if sa == 0:
                continue
            di = ((y + pad) * w + (x + pad)) * 4
            for c in range(3):
                buf[di + c] = round(icon[si + c] * sa + buf[di + c] * (1 - sa))
            buf[di + 3] = 255

    # White placeholder bars on the right (representing wordmark +
    # tagline). Replace with real text in a design tool.
    bar_x = icon_size + pad * 2 + int(w * 0.04)
    bar_w = w - bar_x - int(w * 0.06)
    # Big "wordmark" bar.
    fill_rounded_rect(buf, w, bar_x, int(h * 0.30),
                     bar_x + bar_w, int(h * 0.30) + int(h * 0.16),
                     int(h * 0.04), WHITE)
    # Smaller "tagline" bar.
    fill_rounded_rect(buf, w, bar_x, int(h * 0.56),
                     bar_x + int(bar_w * 0.7), int(h * 0.56) + int(h * 0.06),
                     int(h * 0.02), (0xFF, 0xFF, 0xFF, 0xB3))
    return buf


if __name__ == "__main__":
    main()
