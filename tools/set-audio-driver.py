#!/usr/bin/env python3
"""set-audio-driver.py <prefix> <driver> — set [Software\\Wine\\Drivers] "Audio"=<driver>
in a Wine prefix's user.reg by direct file edit (wineserver must be stopped;
`wine reg add` does not persist on this stack). Idempotent; VERIFIES the edit
by re-reading the file and exits non-zero if the value is not in place.

Bug history (2026-11-16): the first version matched section headers with an
exact string comparison, but Wine writes section headers with a trailing
timestamp (``[Software\\\\Wine\\\\Drivers] 1794756852``), so the match never
fired, the file was rewritten unchanged, and the script still printed
"set Audio=..." — a silent no-op that left Wine on ALSA while the launcher
believed pulse was configured. Section headers are now matched by regex
with an optional trailing timestamp, and the result is verified.
"""
import re
import sys

SECTION_RE = re.compile(r'^\[Software\\\\Wine\\\\Drivers\](\s+\d+)?$')
AUDIO_RE = re.compile(r'^\s*"Audio"\s*=')


def main(prefix, driver):
    path = prefix.rstrip('/') + '/user.reg'
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            text = f.read()
    except FileNotFoundError:
        print(f"no user.reg at {path}; skipping")
        return 1
    section = r'[Software\\Wine\\Drivers]'
    audio_line = f'"Audio"="{driver}"'
    lines = text.split('\n')
    out = []
    in_drivers = False
    done = False
    for ln in lines:
        if SECTION_RE.match(ln.strip()):
            in_drivers = True
            out.append(ln)
            continue
        if in_drivers:
            if ln.startswith('['):
                if not done:
                    out.append(audio_line)
                    done = True
                in_drivers = False
                out.append(ln)
                continue
            if AUDIO_RE.match(ln):
                out.append(audio_line)
                done = True
                continue
        out.append(ln)
    if in_drivers and not done:
        out.append(audio_line)
        done = True
    if not done:
        # No Drivers section at all: append one.
        out.append('')
        out.append(section)
        out.append(audio_line)
    new_text = '\n'.join(out)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(new_text)
    # Verify by re-reading.
    with open(path, encoding='utf-8', errors='replace') as f:
        check = f.read()
    m = re.search(r'\[Software\\\\Wine\\\\Drivers\][^\[]*?"Audio"="([^"]*)"',
                  check, re.S)
    if m and m.group(1) == driver:
        print(f"set Audio={driver} in {path} (verified)")
        return 0
    print(f"FAILED to set Audio={driver} in {path} (found: "
          f"{m.group(1) if m else 'no Drivers/Audio entry'})", file=sys.stderr)
    return 1


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("usage: set-audio-driver.py <prefix> <driver>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
