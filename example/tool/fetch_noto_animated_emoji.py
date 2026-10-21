#!/usr/bin/env python3
"""Fetches the demo's animated emoji pack from Google's Noto Animated Emoji.

Animated Noto Emoji is licensed under CC BY 4.0
(https://creativecommons.org/licenses/by/4.0/); the credit the licence asks
for is in assets/animated_emoji/LICENSE.md, which this script writes too.

The files Google serves are 512 x 512 animated WebP of about 370 KB each. The
demo draws them in emoji cells and inline in text, about 32 logical pixels at
most (96 physical at density 3), so each one is resized to SIZE pixels and
re-encoded at about 120 KB: the pack stays a small part of the app and every
decode is cheap. Frame timing is kept as served.

Usage (from the example directory; needs Pillow):

    python3 tool/fetch_noto_animated_emoji.py

The emoji are listed in EMOJI below, in the order the pack shows them. The
Dart side (lib/src/features/chat/data/animated_emoji_pack.dart) lists the
same code points; a file this script writes and the pack does not list is
never shown.
"""

import io
import os
import sys
import urllib.request

from PIL import Image

SIZE = 96
QUALITY = 70
URL = "https://fonts.gstatic.com/s/e/notoemoji/latest/{code}/512.webp"
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "animated_emoji")

# Code point sequences as Google names them (lower-case hex, joined by "_").
EMOJI = [
    "1f600", "1f604", "1f602", "1f923", "1f60a", "1f607", "1f643", "1f609",
    "1f60d", "1f970", "1f618", "1f61c", "1f92a", "1f60e", "1f913", "1f973",
    "1f929", "1f914", "1f644", "1f62c", "1f631", "1f62d", "1f621", "1f92f",
    "1f971", "1f44d", "1f64f", "1f525", "2728", "1f389", "2764_fe0f", "1f680",
]

LICENSE = """# Animated emoji

The animated WebP files in this directory are from Google's
[Noto Animated Emoji](https://googlefonts.github.io/noto-emoji-animation/),
resized to {size} x {size} pixels by `tool/fetch_noto_animated_emoji.py`.

Animated Noto Emoji is licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/legalcode). Credit:
Google, Noto Emoji. Changes: resized and re-encoded.
"""


def fetch(code: str) -> bytes:
    with urllib.request.urlopen(URL.format(code=code), timeout=30) as response:
        return response.read()


def resize(data: bytes) -> bytes:
    source = Image.open(io.BytesIO(data))
    frames, durations = [], []
    for index in range(source.n_frames):
        source.seek(index)
        frames.append(
            source.convert("RGBA").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
        )
        durations.append(source.info.get("duration", 100))
    out = io.BytesIO()
    frames[0].save(
        out,
        format="WEBP",
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        quality=QUALITY,
        # minimize_size saves about 13 % here at many times the encode time.
        method=6,
    )
    return out.getvalue()


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    total = 0
    for code in EMOJI:
        data = resize(fetch(code))
        with open(os.path.join(OUT, f"{code}.webp"), "wb") as file:
            file.write(data)
        total += len(data)
        print(f"{code}.webp {len(data) // 1024} KiB")
    with open(os.path.join(OUT, "LICENSE.md"), "w", encoding="utf-8") as file:
        file.write(LICENSE.format(size=SIZE))
    print(f"{total // 1024} KiB in all")
    return 0


if __name__ == "__main__":
    sys.exit(main())
