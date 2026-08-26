#!/usr/bin/env python3
"""Generate the app icon in the aqua art direction, with no design tool.

There is no image library on the build machine and no Mac to open Sketch on, so
the icon is drawn here from arithmetic and written as a raw PNG. Re-run after
editing the constants:

    python scripts/make-app-icon.py

iOS requires the 1024 icon to be fully opaque with no alpha channel and no
pre-applied corner rounding - the system masks it. So this writes 8-bit RGB
(PNG colour type 2), which cannot carry alpha even by accident.
"""
import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
OUT = Path(__file__).resolve().parent.parent / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

# design/screen-study.html
AQUA_400 = (0x5B, 0xDD, 0xE1)
AQUA_600 = (0x1F, 0xB2, 0xB8)
DEEP = (0x0B, 0x3A, 0x42)
FOAM = (0xFF, 0xFF, 0xFF)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def blend(base, over, amount):
    return lerp(base, over, max(0.0, min(1.0, amount)))


def pixel(x, y):
    """Sky above, sea below, and three foam lines running across the face."""
    v = y / (SIZE - 1)

    # Vertical gradient: bright aqua at the top falling to deep water.
    if v < 0.5:
        colour = lerp(AQUA_400, AQUA_600, v / 0.5)
    else:
        colour = lerp(AQUA_600, DEEP, (v - 0.5) / 0.5)

    # Three offset sine crests. Different wavelengths so they read as swell
    # rather than as a repeating pattern.
    u = x / (SIZE - 1)
    for centre, cycles, phase, thickness in (
        (0.42, 1.6, 0.0, 0.030),
        (0.58, 1.2, 1.9, 0.024),
        (0.72, 2.1, 3.4, 0.018),
    ):
        crest = centre + 0.055 * math.sin(2 * math.pi * cycles * u + phase)
        distance = abs(v - crest)
        if distance < thickness:
            # Soft edge, so the curve does not alias into a staircase.
            colour = blend(colour, FOAM, 1.0 - (distance / thickness) ** 2)

    return colour


def write_png(path, size, shader):
    raw = bytearray()
    for y in range(size):
        raw.append(0)  # filter type 0 (None) for this scanline
        for x in range(size):
            raw.extend(shader(x, y))

    def chunk(kind, payload):
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    # width, height, bit depth 8, colour type 2 (truecolour, no alpha)
    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


if __name__ == "__main__":
    write_png(OUT, SIZE, pixel)
    print("wrote %s (%d bytes)" % (OUT, OUT.stat().st_size))
