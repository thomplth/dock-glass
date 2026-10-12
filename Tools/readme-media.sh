#!/bin/zsh
# Builds the README figures in media/ from glass-fit captures and renders. Needs ImageMagick.
#
#   Tools/readme-media.sh <captures dir>
#
# The captures dir holds, for each figure:
#   27/{light,dark}/            glass-fit capture of macOS 27 at tint 0, then `glass-fit fit --max-evals 0
#                               --keep` renders copied to readme/{dockglass,inactive,clear}-{A,B}.png
#                               (default, `--focus inactive`, `--base clear --untuned --focus window`)
#   27/dark-tint{0.25,0.5,0.75,1}/  the same at each tint, readme/dockglass-{A,B}.png only
#   26/{light,dark}/            macOS 26 capture and its evalA/evalB.png
#   demo-{light,dark}.png       `dockglass-demo --capture`
#
# macOS 27's figures show only the two ends of the plate, so the captures can come from a switcher
# with any apps open: the left end holds glass-fit's own icon and the right end the last app,
# which must be a stock one. macOS 26's captures must show only stock apps.
set -euo pipefail
src="${1:?captures dir}"
out="${0:A:h:h}/media"
font=/System/Library/Fonts/SFNS.ttf
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Pixel geometry of glass-fit's 300pt capture strip at 2x: the plate is 176pt tall from y = 62pt.
top=108 height=384       # the plate's top less 8pt, and its height plus 8pt each side
endWidth=326             # 163pt: 8pt outside the plate to just past the first or last icon

palette() {
    if [[ $1 == light ]]; then bg='#ffffff'; fg='#1f2328'; else bg='#0d1117'; fg='#e6edf3'; fi
}

# The two ends of a 2320pt (17-app) macOS 27 plate centred on a 2560pt screen, joined by a seam.
ends() {
    magick "$1" -alpha off \( -clone 0 -crop ${endWidth}x$height+224+$top +repage \) \
        \( -clone 0 -crop ${endWidth}x$height+4570+$top +repage \) -delete 0 \
        \( -size 6x$height xc:"$bg" \) -swap 1,2 +append "$2"
}

# A 4-app macOS 26 plate (578pt) centred on a 1024pt screen, whole.
plate26() {
    magick "$1" -alpha off -crop 1188x$height+430+$top +repage "$2"
}

# Per-channel absolute difference, amplified 10x.
diff10() {
    magick "$1" "$2" -alpha off -compose difference -composite -evaluate multiply 10 "$3"
}

# The top-left corner of a macOS 27 plate, 44pt square from 6pt outside it, enlarged 4x.
corner() {
    magick "$1" -alpha off -crop 88x88+228+112 +repage -filter point -resize 400% "$2"
}

label() { # text width height file [size]
    magick -size "$2x$3" xc:"$bg" -font $font -pointsize "${5:-30}" -fill "$fg" -gravity west \
        -annotate +24+0 "$1" "$4"
}
header() { # text width file
    magick -size "$2x64" xc:"$bg" -font $font -pointsize 28 -fill "$fg" -gravity center \
        -annotate +0+0 "$1" "$3"
}

# Rows of [label, cell, cell...] with a header row, 12px gutters, on the appearance's background.
# grid <out> <label width> <cell width> <cell height> <header...> -- <label> <cells...> -- ...
grid() {
    local file=$1 lw=$2 cw=$3 ch=$4; shift 4
    local -a rows headers cells
    local n=0 r=0
    label "" $lw 64 "$tmp/h0.png"; headers=("$tmp/h0.png")
    while [[ $1 != -- ]]; do n=$((n + 1)); header "$1" $cw "$tmp/h$n.png"; headers+=("$tmp/h$n.png"); shift; done
    shift
    magick "${headers[@]}" -background "$bg" -splice 12x0 +append -chop 12x0 "$tmp/row0.png"
    rows=("$tmp/row0.png")
    while (( $# )); do
        r=$((r + 1))
        label "$1" $lw $ch "$tmp/l$r.png"; shift
        cells=("$tmp/l$r.png")
        while (( $# )) && [[ $1 != -- ]]; do cells+=("$1"); shift; done
        (( $# )) && shift
        magick "${cells[@]}" -background "$bg" -splice 12x0 +append -chop 12x0 "$tmp/row$r.png"
        rows+=("$tmp/row$r.png")
    done
    magick "${rows[@]}" -background "$bg" -splice 0x12 -append -chop 0x12 -bordercolor "$bg" -border 24 "$file"
}

for mode in light dark; do
    palette $mode
    d="$src/27/$mode"
    for b in A B; do
        ends "$d/native$b.png" "$tmp/n$b.png"
        for v in dockglass inactive clear; do ends "$d/readme/$v-$b.png" "$tmp/$v$b.png"; done
        diff10 "$tmp/n$b.png" "$tmp/dockglass$b.png" "$tmp/d$b.png"
        corner "$d/native$b.png" "$tmp/cn$b.png"
        for v in dockglass inactive clear; do corner "$d/readme/$v-$b.png" "$tmp/c$v$b.png"; done
        diff10 "$tmp/cn$b.png" "$tmp/cdockglass$b.png" "$tmp/cd$b.png"
    done
    grid "$out/macos27-$mode.png" 300 658 $height "Backdrop A" "Backdrop B" -- \
        "Native" "$tmp/nA.png" "$tmp/nB.png" -- \
        "DockGlass" "$tmp/dockglassA.png" "$tmp/dockglassB.png" -- \
        "Difference ×10" "$tmp/dA.png" "$tmp/dB.png"
    grid "$out/focus-27-$mode.png" 300 658 $height "Native" "DockGlass" "DockGlass .inactive" "SwiftUI .clear" -- \
        "Backdrop A" "$tmp/nA.png" "$tmp/dockglassA.png" "$tmp/inactiveA.png" "$tmp/clearA.png" -- \
        "Backdrop B" "$tmp/nB.png" "$tmp/dockglassB.png" "$tmp/inactiveB.png" "$tmp/clearB.png"
    grid "$out/rim-27-$mode.png" 300 352 352 "Native" "DockGlass" "Difference ×10" ".inactive" "SwiftUI .clear" -- \
        "Backdrop A" "$tmp/cnA.png" "$tmp/cdockglassA.png" "$tmp/cdA.png" "$tmp/cinactiveA.png" "$tmp/cclearA.png" -- \
        "Backdrop B" "$tmp/cnB.png" "$tmp/cdockglassB.png" "$tmp/cdB.png" "$tmp/cinactiveB.png" "$tmp/cclearB.png"

    d="$src/26/$mode"
    for b in A B; do
        plate26 "$d/native$b.png" "$tmp/n26$b.png"
        plate26 "$d/eval$b.png" "$tmp/e26$b.png"
        diff10 "$tmp/n26$b.png" "$tmp/e26$b.png" "$tmp/d26$b.png"
    done
    grid "$out/macos26-$mode.png" 300 1188 $height "Backdrop A" "Backdrop B" -- \
        "Native" "$tmp/n26A.png" "$tmp/n26B.png" -- \
        "DockGlass" "$tmp/e26A.png" "$tmp/e26B.png" -- \
        "Difference ×10" "$tmp/d26A.png" "$tmp/d26B.png"

    cp "$src/demo-$mode.png" "$out/demo-$mode.png"
done

palette dark
args=()
for t in 0 0.25 0.5 0.75 1; do
    d="$src/27/dark-tint$t"
    [[ $t == 0 ]] && d="$src/27/dark"
    ends "$d/nativeA.png" "$tmp/tn$t.png"
    ends "$d/readme/dockglass-A.png" "$tmp/te$t.png"
    diff10 "$tmp/tn$t.png" "$tmp/te$t.png" "$tmp/td$t.png"
    args+=("Tint $t" "$tmp/tn$t.png" "$tmp/te$t.png" "$tmp/td$t.png" --)
done
grid "$out/tint-27-dark.png" 300 658 $height "Native" "DockGlass" "Difference ×10" -- "${args[@]}"
