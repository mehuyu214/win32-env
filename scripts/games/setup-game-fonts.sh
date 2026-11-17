#!/bin/bash
# setup-game-fonts.sh <prefix> — fix Japanese tofu in a games prefix.
# Replaces the bitmap "System" font path with subsetted IPA Gothic faces:
#   systemjp.ttf  (family "System") — the face win32u actually selects
#   ipag.ttf      (family IPAGothic) — the FontSubstitutes target
# The stock jvgasys.fon / Tahoma are moved aside (backup dir next to the
# prefix), their Fonts registry entries removed, and FontSubstitutes are
# pointed at IPAGothic. cp932 is then used for CJK code pages.
# Fonts are generated with tools/make-subset-fonts.py from an IPA Gothic
# source, resolved in this order: the explicit [ipag.ttf] argument, the
# prefix's own Fonts/ipag.ttf (re-runs), then fonts-src/ipag.ttf at the
# repo root — fetch that one with: scripts/fetch-online.sh fonts-ipag
# (extracts ipag.ttf from Ubuntu's fonts-ipafont-gothic package).
# Idempotent; safe to re-run. The prefix's wineserver must be stopped.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${1:?usage: setup-game-fonts.sh <wineprefix> [ipag.ttf]}"
SRC_ROOT="${VN32_ROOT:-$(cd "$HERE/../.." && pwd)}"
if [ $# -ge 2 ]; then
  IPAG_SRC="$2"
elif [ -f "$PREFIX/drive_c/windows/Fonts/ipag.ttf" ]; then
  IPAG_SRC="$PREFIX/drive_c/windows/Fonts/ipag.ttf"
elif [ -f "$SRC_ROOT/fonts-src/ipag.ttf" ]; then
  IPAG_SRC="$SRC_ROOT/fonts-src/ipag.ttf"
else
  IPAG_SRC=""
fi
if [ -z "$IPAG_SRC" ] || [ ! -f "$IPAG_SRC" ]; then
  echo "IPA Gothic source not found${IPAG_SRC:+: $IPAG_SRC}" >&2
  echo "pass an ipag.ttf path, or fetch the source first: scripts/fetch-online.sh fonts-ipag" >&2
  echo "(extracts ipag.ttf from Ubuntu's fonts-ipafont-gothic package into fonts-src/)" >&2
  exit 1
fi
GEN="$PREFIX/../.fontgen"
mkdir -p "$GEN"
python3 "$VN32_ROOT/tools/make-subset-fonts.py" "$IPAG_SRC" "$GEN" || exit 1
FONTS="$PREFIX/drive_c/windows/Fonts"
mkdir -p "$FONTS"
BAK="$PREFIX/fonts-bak"
mkdir -p "$BAK"
for f in tahoma.ttf tahomabd.ttf jvgasys.fon jvgafix.fon; do
  if [ -e "$FONTS/$f" ]; then mv "$FONTS/$f" "$BAK/$f" && echo "moved $f -> fonts-bak/"; fi
done
cp "$GEN/systemjp.ttf" "$GEN/ipag.ttf" "$FONTS/"
echo "installed systemjp.ttf + ipag.ttf into $FONTS"
python3 - "$PREFIX" << 'PYEOF'
import sys, re
prefix = sys.argv[1]
# system.reg: Fonts key — drop Tahoma entries, register the two subset faces
sp = prefix + '/system.reg'
t = open(sp, encoding='utf-8', errors='replace').read()
lines = t.split('\n')
out = []
in_fonts = False
have_system = have_ipag = False
for ln in lines:
    if ln.strip().startswith(r'[Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts]'):
        in_fonts = True
        out.append(ln)
        continue
    if in_fonts:
        if ln.startswith('['):
            if not have_system:
                out.append('"System (TrueType)"="systemjp.ttf"')
                have_system = True
            if not have_ipag:
                out.append('"IPAGothic (TrueType)"="ipag.ttf"')
                have_ipag = True
            in_fonts = False
            out.append(ln)
            continue
        if re.match(r'^\s*"(Tahoma|Tahoma Bold|System \(TrueType\)|IPAGothic \(TrueType\))"', ln):
            if 'System (TrueType)' in ln:
                out.append('"System (TrueType)"="systemjp.ttf"'); have_system = True
            elif 'IPAGothic (TrueType)' in ln:
                out.append('"IPAGothic (TrueType)"="ipag.ttf"'); have_ipag = True
            continue  # drop old Tahoma / stale entries
    out.append(ln)
open(sp, 'w', encoding='utf-8').write('\n'.join(out))
# user.reg: FontSubstitutes -> IPAGothic for the usual dialog faces
up = prefix + '/user.reg'
t = open(up, encoding='utf-8', errors='replace').read()
sec = r'[Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes]'
subs = {'MS Shell Dlg': 'IPAGothic', 'MS Shell Dlg 2': 'IPAGothic',
        'MS Gothic': 'IPAGothic', 'MS PGothic': 'IPAGothic',
        'MS UI Gothic': 'IPAGothic', 'Tahoma': 'IPAGothic'}
if sec in t:
    lines = t.split('\n')
    out = []
    in_sub = False
    for ln in lines:
        if ln.strip() == sec:
            in_sub = True
            out.append(ln)
            continue
        if in_sub:
            if ln.startswith('['):
                for k, v in subs.items():
                    if not any(l.startswith(f'"{k}"=') for l in out):
                        out.append(f'"{k}"="{v}"')
                in_sub = False
                out.append(ln)
                continue
            m = re.match(r'^\s*"([^"]+)"\s*=', ln)
            if m and m.group(1) in subs:
                out.append(f'"{m.group(1)}"="{subs[m.group(1)]}"')
                continue
        out.append(ln)
    t = '\n'.join(out)
else:
    t = t.rstrip('\n') + '\n\n' + sec + '\n' + '\n'.join(f'"{k}"="{v}"' for k, v in subs.items()) + '\n'
open(up, 'w', encoding='utf-8').write(t)
print("registry updated (Fonts + FontSubstitutes)")
PYEOF
