#!/usr/bin/env bash
# =============================================================================
# A kimenetek/ mappában lévő fájlokat változtatás nélkül, ``` code blockban
# beilleszti a dokumentáció jelölt helyeire:
#
#   <!-- KIMENET:segedscript-kimenet-sbx.txt -->
#   ...  (ezt a részt cseréli)
#   <!-- /KIMENET -->
#
# Használat: ./kimenetek-beillesztese.sh   (a létrehozó scriptek után)
# =============================================================================
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="${REPO_ROOT}/dokumentacio/kornyezetigenyles.md"
OUT_DIR="${REPO_ROOT}/kimenetek"

tmp="$(mktemp)"
awk -v outdir="$OUT_DIR" '
  match($0, /^<!-- KIMENET:[^ ]+ -->$/) {
    print
    file = substr($0, 14, length($0) - 17)
    path = outdir "/" file
    print "```"
    if ((getline line < path) > 0) {
      print line
      while ((getline line < path) > 0) print line
      close(path)
    } else {
      print "(még nincs kimenet: kimenetek/" file " – futtasd a létrehozó scriptet)"
    }
    print "```"
    skip = 1
    next
  }
  /^<!-- \/KIMENET -->$/ { skip = 0 }
  !skip { print }
' "$DOC" > "$tmp"
mv "$tmp" "$DOC"
echo "Kimenetek beillesztve: ${DOC#$REPO_ROOT/}"
grep -o '<!-- KIMENET:[^ ]* -->' "$DOC" | sed 's/<!-- KIMENET:/  - /; s/ -->//'
