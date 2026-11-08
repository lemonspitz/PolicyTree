#!/bin/zsh
# Mac only: renders the Liquid Glass icon document into the Windows icon files, which are committed.
set -euo pipefail
cd "$(dirname "$0")"
ICT="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
T=$(mktemp -d)
"$ICT" ../Resources/AppIcon.icon --export-image --output-file "$T/full.png" --platform macOS --rendition Default --width 512 --height 512 --scale 2 > /dev/null
sips -z 512 512 "$T/full.png" --out policytree/icon.png > /dev/null
for s in 16 24 32 48 64 128 256; do sips -z $s $s "$T/full.png" --out "$T/$s.png" > /dev/null; done
python3 - "$T" policytree/icon.ico <<'PY'
import struct, sys
folder, out = sys.argv[1:]
sizes = [16, 24, 32, 48, 64, 128, 256]
blobs = [open(f"{folder}/{s}.png", "rb").read() for s in sizes]
head = struct.pack("<HHH", 0, 1, len(sizes))
offset = 6 + 16 * len(sizes)
entries = b""
for s, b in zip(sizes, blobs):
    entries += struct.pack("<BBBBHHII", s % 256, s % 256, 0, 0, 1, 32, len(b), offset)
    offset += len(b)
open(out, "wb").write(head + entries + b"".join(blobs))
PY
rm -rf "$T"
echo "icon.png dan icon.ico dibuat"
