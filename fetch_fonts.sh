#!/usr/bin/env bash
# ============================================================================
# fetch_fonts.sh
#
# Vendors Google Fonts as local .woff2 files so the portfolio can run fully
# offline. Run this ONLY when you have internet access — the portfolio
# itself never needs to be online.
#
# WHAT IT DOES:
#   1. Reads the FONTS list below.
#   2. Downloads the matching .woff2 files from Google Fonts into
#      assets/fonts/
#   3. Writes assets/fonts/fonts.css with @font-face rules pointing at
#      those local files.
#   4. Compares against last run's manifest and deletes any .woff2 files
#      that are no longer needed (e.g. you removed a font from the list).
#
# HOW TO ADD/REMOVE A FONT:
#   Just edit the FONTS array below, then rerun this script.
#   Format:  "Font Name:weight1,weight2"
#   (Use + instead of spaces is NOT needed — spaces in the name are fine,
#   the script handles the URL-encoding for you.)
#
# USAGE:
#   cd into the "portfolio" folder (the one containing this script and the
#   "assets" folder), then:
#     chmod +x fetch_fonts.sh
#     ./fetch_fonts.sh
# ============================================================================

set -euo pipefail

FONTS=(
  "VT323:400"
  "Press Start 2P:400"
)

ASSET_DIR="assets/fonts"
CSS_OUT="$ASSET_DIR/fonts.css"
MANIFEST="$ASSET_DIR/.manifest"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

mkdir -p "$ASSET_DIR"

# ---- build the Google Fonts CSS2 request URL ----
url="https://fonts.googleapis.com/css2?display=swap"
for entry in "${FONTS[@]}"; do
  name="${entry%%:*}"
  weights="${entry##*:}"
  encoded_name="$(printf '%s' "$name" | sed 's/ /+/g')"
  url="${url}&family=${encoded_name}:wght@${weights}"
done

echo "Fetching font CSS from Google Fonts..."
css="$(curl -fsSL -A "$UA" "$url")" || {
  echo "ERROR: could not reach Google Fonts. Check your internet connection." >&2
  exit 1
}

if [ -z "$css" ]; then
  echo "ERROR: Google Fonts returned an empty response." >&2
  exit 1
fi

# ---- pull out every font file URL referenced in the CSS ----
mapfile -t font_urls < <(grep -oE 'https://fonts\.gstatic\.com/[^)]+\.woff2' <<< "$css" | sort -u)

if [ "${#font_urls[@]}" -eq 0 ]; then
  echo "ERROR: no font files found in the response. Font names/weights may be wrong." >&2
  exit 1
fi

echo "Found ${#font_urls[@]} font file(s). Downloading..."

new_manifest=()
rewritten_css="$css"

for furl in "${font_urls[@]}"; do
  fname="$(basename "$furl")"
  echo "  -> $fname"
  curl -fsSL "$furl" -o "$ASSET_DIR/$fname"
  new_manifest+=("$fname")
  # point the CSS at the local file instead of the remote one
  rewritten_css="${rewritten_css//$furl/$fname}"
done

printf '%s\n' "$rewritten_css" > "$CSS_OUT"
echo "Wrote $CSS_OUT"

# ---- clean up fonts that are no longer referenced ----
if [ -f "$MANIFEST" ]; then
  while IFS= read -r old_file; do
    [ -z "$old_file" ] && continue
    keep=0
    for f in "${new_manifest[@]}"; do
      [ "$f" = "$old_file" ] && keep=1 && break
    done
    if [ "$keep" -eq 0 ] && [ -f "$ASSET_DIR/$old_file" ]; then
      echo "  removing unused font: $old_file"
      rm -f "$ASSET_DIR/$old_file"
    fi
  done < "$MANIFEST"
fi

printf '%s\n' "${new_manifest[@]}" > "$MANIFEST"

echo "Done. $(($(wc -l < "$MANIFEST"))) font file(s) vendored in $ASSET_DIR/"
