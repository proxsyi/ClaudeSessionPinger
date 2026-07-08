#!/usr/bin/env python3
"""
Packs the AppIcon.iconset PNGs into a real macOS .icns file by hand.

The sandbox has no `iconutil` (macOS-only), and this environment's
ImageMagick build has no ICNS delegate, so this constructs the icns
container directly: a 4-byte 'icns' magic + big-endian total length,
followed by one chunk per icon size (4-byte OSType tag + big-endian
chunk length + raw PNG bytes). This is the standard modern (10.7+)
PNG-backed icns layout that Finder and Xcode both read natively.
"""
import os
import struct

ICONSET = os.path.join(os.path.dirname(__file__), "AppIcon.iconset")
OUT_PATH = os.path.join(os.path.dirname(__file__), "AppIcon.icns")

# (OSType tag, source PNG in the .iconset)
ENTRIES = [
    (b"icp4", "icon_16x16.png"),
    (b"ic11", "icon_16x16@2x.png"),
    (b"icp5", "icon_32x32.png"),
    (b"ic12", "icon_32x32@2x.png"),
    (b"ic07", "icon_128x128.png"),
    (b"ic13", "icon_128x128@2x.png"),
    (b"ic08", "icon_256x256.png"),
    (b"ic14", "icon_256x256@2x.png"),
    (b"ic09", "icon_512x512.png"),
    (b"ic10", "icon_512x512@2x.png"),
]


def main() -> None:
    body = b""
    for tag, filename in ENTRIES:
        with open(os.path.join(ICONSET, filename), "rb") as f:
            png_bytes = f.read()
        chunk_len = 8 + len(png_bytes)
        body += tag + struct.pack(">I", chunk_len) + png_bytes

    total_len = 8 + len(body)
    header = b"icns" + struct.pack(">I", total_len)

    with open(OUT_PATH, "wb") as f:
        f.write(header + body)

    print(f"Wrote {OUT_PATH} ({total_len} bytes, {len(ENTRIES)} sizes)")


if __name__ == "__main__":
    main()
