#!/usr/bin/env bash
# Procedurally generate per-agent lock-screen mascots (Clawd-style chunky pixel art).
#
# These sprites are STATIC committed assets (assets/mascots/*.png), NOT built by Nix —
# hyprlock's avatar reload_cmd references them by literal ~/nix-config path, exactly like
# the existing assets/clawd-frame-*.png. Re-run this by hand whenever you tweak the art,
# then re-commit the PNGs:   out=assets/mascots bash home/linux/mascot-gen.sh
# Requires `magick` (ImageMagick 7) on PATH and $out set to the output dir. Output is
# byte-reproducible (no embedded timestamps), so a no-op re-run produces no git diff.
#
# Each mascot is drawn on a 16x16 grid (one char = one pixel), then point-scaled x20 to
# 320x320 over a transparent background — matching the committed clawd-frame-*.png sprites.
# 4 frames each → a slow idle animation (the avatar reload_cmd cycles them ~1fps).
#   codex    → teal blob, wiggling antennae, a roaming belly glint
#   gemini   → blue 4-point sparkle-star, twinkles (drawn as a polygon)
#   opencode → amber blocky bot, blinking antenna LEDs + a scrolling scanline mouth
set -euo pipefail

OUT="${out:?out must be set}"
mkdir -p "$OUT"

# char -> hex colour. '.' (and any unmapped char) is transparent. 'e' is shared eye-dark.
declare -A COLOR=(
  [t]='#10A37F' [h]='#7DF0CE'                         # codex teal / glint
  [a]='#E0AF68' [A]='#A9802F' [s]='#9ECE6A' [k]='#15151F'  # opencode amber/shade/screen-green/screen-dark
  [e]='#1A1A2E'                                        # eyes
)

# render OUTFILE row0 ... row15  (exactly 16 strings of 16 chars)
render() {
  local out="$1"; shift
  local -a args=(-size 16x16 xc:none)
  local y=0 row x c col
  for row in "$@"; do
    (( ${#row} == 16 )) || { echo "mascot-gen: row $y is ${#row} chars (need 16): '$row'" >&2; exit 1; }
    for (( x=0; x<16; x++ )); do
      c="${row:x:1}"
      [[ $c == . ]] && continue
      col="${COLOR[$c]:-}"
      [[ -z $col ]] && continue
      args+=(-fill "$col" -draw "point $x,$y")
    done
    (( y++ )) || true
  done
  (( y == 16 )) || { echo "mascot-gen: $out got $y rows (need 16)" >&2; exit 1; }
  # -strip + excluding date/time chunks keeps output byte-reproducible (no wall-clock
  # timestamp baked into the PNG), so re-running this script yields no spurious git churn.
  magick "${args[@]}" -scale 320x320 -strip -define png:exclude-chunks=date,time "$out"
}

###############################################################################
# CODEX — teal rounded blob; antennae wiggle, a light glint roams the belly.
###############################################################################
codex_base=(
  "................"
  ".....e....e....."   # 1  antennae tips      (per-frame)
  ".....t....t....."   # 2  antennae stalks    (per-frame)
  "....tttttttt...."   # 3
  "...tttttttttt..."   # 4
  "..tttttttttttt.."   # 5
  "..tttttttttttt.."   # 6
  "..tttettttettt.."   # 7  eyes
  "..tttttttttttt.."   # 8
  "..tttttttttttt.."   # 9
  "..tttttttttttt.."   # 10 glint            (per-frame)
  "...tttttttttt..."   # 11
  "....tttttttt...."   # 12
  "....tt....tt...."   # 13 feet
  "................"
  "................"
)
codex_emit() {  # idx  row0  row1  row2  row10
  local -a f=("${codex_base[@]}")
  f[0]="$2"; f[1]="$3"; f[2]="$4"; f[10]="$5"
  render "$OUT/codex-frame-$1.png" "${f[@]}"
}
codex_emit 0 "................" ".....e....e....." ".....t....t....." "..tttttthttttt.."
codex_emit 1 "................" "....e......e...." ".....t....t....." "..tttthttttttt.."
codex_emit 2 "................" ".....e....e....." ".....t....t....." "..tttttttthttt.."
codex_emit 3 "................" "......e..e......" ".....t....t....." "..ttttthtttttt.."

###############################################################################
# OPENCODE — amber bot; antenna LEDs blink, eyes blink, scanline mouth scrolls.
###############################################################################
SCR="..aAkkkkkkkkAa.."     # blank screen row
MOUTH="..aAksssssskAa.."   # green scanline mouth
EYES="..aAksskksskAa.."    # two green eyes
oc_base=(
  "................"
  "....s......s...."   # 1  antenna LEDs (per-frame)
  "....a......a...."   # 2
  "....a......a...."   # 3
  "..aaaaaaaaaaaa.."   # 4
  "..aAAAAAAAAAAa.."   # 5
  "..aAkkkkkkkkAa.."   # 6  screen top
  "..aAksskksskAa.."   # 7  eyes        (per-frame)
  "..aAkkkkkkkkAa.."   # 8  screen      (per-frame)
  "..aAkkkkkkkkAa.."   # 9  screen      (per-frame, mouth)
  "..aAkkkkkkkkAa.."   # 10 screen      (per-frame, mouth)
  "..aAAAAAAAAAAa.."   # 11
  "..aaaaaaaaaaaa.."   # 12
  "...aa....aa....."   # 13 feet
  "................"
  "................"
)
oc_emit() {  # idx  led-row  eyes-row  r8  r9  r10
  local -a f=("${oc_base[@]}")
  f[1]="$2"; f[7]="$3"; f[8]="$4"; f[9]="$5"; f[10]="$6"
  render "$OUT/opencode-frame-$1.png" "${f[@]}"
}
oc_emit 0 "....s......s...." "$EYES" "$SCR"   "$MOUTH" "$SCR"
oc_emit 1 "....a......a...." "$EYES" "$SCR"   "$SCR"   "$MOUTH"
oc_emit 2 "....s......s...." "$SCR"  "$MOUTH" "$SCR"   "$SCR"
oc_emit 3 "....a......a...." "$EYES" "$SCR"   "$MOUTH" "$SCR"

###############################################################################
# GEMINI — blue 4-point sparkle-star, twinkles. Drawn as a polygon (+antialias off
# keeps the scaled-up edges chunky like the pixmap mascots), with a roaming white
# sparkle dot and a pulse between full/small sizes.
###############################################################################
gemini_emit() {  # idx  poly  sparkle-x  sparkle-y  blink(0/1)
  local idx="$1" poly="$2" sx="$3" sy="$4" blink="$5"
  local -a a=(-size 16x16 xc:none +antialias
    -fill '#4285F4' -draw "polygon $poly"
    -fill '#8AB4F8' -draw "polygon 8,4 10,7 8,10 6,7")    # lighter core diamond (chunky)
  if [[ $blink == 1 ]]; then
    a+=(-fill '#15151F' -draw "rectangle 6,7 7,7" -draw "rectangle 9,7 10,7")  # closed eyes
  else
    a+=(-fill '#15151F' -draw "point 6,7" -draw "point 9,7")
  fi
  a+=(-fill '#FFFFFF' -draw "point $sx,$sy" -draw "point $((sx+1)),$sy")        # sparkle glint
  magick "${a[@]}" -scale 320x320 -strip -define png:exclude-chunks=date,time "$OUT/gemini-frame-$idx.png"
}
# Fatter 4-point star: tips pulled 1px off the edge + inner vertices pushed out, so the
# spikes are stubby and the body chunky — matching the weight of the blob/bot mascots.
FULL='8,1 10,6 15,8 10,10 8,15 6,10 1,8 6,6'
SMALL='8,3 9.5,6.5 13,8 9.5,9.5 8,13 6.5,9.5 3,8 6.5,6.5'
gemini_emit 0 "$FULL"  12 3  0
gemini_emit 1 "$SMALL" 12 11 0
gemini_emit 2 "$FULL"  3  11 1
gemini_emit 3 "$SMALL" 3  3  0

echo "mascot-gen: wrote $(ls "$OUT" | wc -l) files to $OUT" >&2
