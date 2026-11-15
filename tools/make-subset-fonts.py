#!/usr/bin/env python3
"""make-subset-fonts.py <ipag.ttf> <outdir>

Build the two subset fonts the "System" font path needs (see
FIXLOG-20261116.md §6 / IMPROVEMENTS.md §4):

  systemjp.ttf — IPA Gothic subset, family renamed to "System" (the face
                 Wine's win32u actually selects for menu/console CJK text;
                 the stock bitmap jvgasys.fon renders tofu for CJK).
  ipag.ttf     — IPA Gothic subset, family kept as IPAGothic (the
                 FontSubstitutes target).

Coverage: ASCII, Latin-1, general punctuation (U+2000-206F),
U+3000-30FF (symbols/hiragana/katakana), U+4E00-9FFF (CJK),
U+FF00-FF9F (full/half-width kana). Subsetting rebuilds cmap/glyf/loca
so CJK glyphs land on small glyph IDs; the full font's large GIDs are
what breaks under this emulation path (observed: 2px slivers / tofu).

Requires fontTools (pyftsubset). Output is deterministic for a given
input font; expect ~10,250 glyphs (maxp numGlyphs) for the 2026-11-12
IPA Gothic source.
"""
import sys, os
from fontTools.ttLib import TTFont
from fontTools import subset

UNICODES = "U+0000-00FF,U+2000-206F,U+3000-30FF,U+4E00-9FFF,U+FF00-FF9F"

def make_subset(src, dst, family=None):
    opts = subset.Options()
    opts.flavor = None
    opts.layout_features = ['*']
    opts.name_IDs = ['*']
    opts.notdef_outline = True
    opts.recalc_bounds = True
    opts.recalc_timestamp = True
    font = subset.load_font(src, opts)
    ss = subset.Subsetter(opts)
    ss.populate(unicodes=subset.parse_unicodes(UNICODES))
    ss.subset(font)
    if family is not None:
        name = font['name']
        for nid in (1, 4, 6, 16):
            name.setName(family, nid, 3, 1, 0x411)
            name.setName(family, nid, 1, 0, 0)
        # keep the style suffix consistent for the RIBBI names
        for rec in name.names:
            if rec.nameID == 2 and rec.platformID == 3:
                name.setName('Regular', 2, 3, 1, 0x411)
    font.save(dst)
    n = font['maxp'].numGlyphs
    print(f"{dst}: {n} glyphs")
    return n

def main():
    src, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    make_subset(src, os.path.join(outdir, 'ipag.ttf'))
    make_subset(src, os.path.join(outdir, 'systemjp.ttf'), family='System')
    return 0

if __name__ == '__main__':
    sys.exit(main())
