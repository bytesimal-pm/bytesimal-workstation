#!/usr/bin/env python
"""
Rescale TH Sarabun New's glyphs 1.4x so it reads the same size as Latin
fonts (Noto Sans, CommitMono) at the same CSS/pixel size.

The upstream font draws its glyphs small within the em-square (x-height
340/1000 vs Noto Sans' 536/1000). Scaling via fontconfig `pixelsize` only
works in Pango/GTK apps; Firefox, Chromium and Qt size fonts from CSS and
ignore it. Baking the scale into the font works everywhere.

Usage:  python rescale.py <original.ttf>...   (overwrites in place)
Needs:  pip install fonttools
"""
import sys
from fontTools.ttLib import TTFont
from fontTools.ttLib.scaleUpem import scale_upem

SCALE = 1.4
# Match Noto Sans so mixed Thai/Latin lines get the same line-height.
# Stacked tone marks overflow the ascender, as they do in Noto Sans Thai.
ASCENT, DESCENT = 1069, -293

for path in sys.argv[1:]:
    f = TTFont(path)
    upem = f["head"].unitsPerEm
    scale_upem(f, round(upem * SCALE))   # scales every table consistently
    f["head"].unitsPerEm = upem          # ...then reinterpret at the old em

    # Hinting was tuned for the original outlines; drop it and let FreeType
    # autohint. DSIG no longer validates a modified font.
    for t in ("cvt ", "fpgm", "prep", "hdmx", "LTSH", "VDMX", "DSIG"):
        if t in f:
            del f[t]
    for g in f["glyf"].glyphs.values():
        if hasattr(g, "program"):
            g.program.fromBytecode(b"")

    hhea, os2, head = f["hhea"], f["OS/2"], f["head"]
    hhea.ascent, hhea.descent, hhea.lineGap = ASCENT, DESCENT, 0
    os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = ASCENT, DESCENT, 0
    os2.version = max(os2.version, 4)    # bit 7 is defined from v4
    os2.fsSelection |= 1 << 7            # USE_TYPO_METRICS
    os2.usWinAscent, os2.usWinDescent = head.yMax, -head.yMin

    f.save(path)
    print(f"{path}: x-height {os2.sxHeight}, bounds {head.yMin}..{head.yMax}")
