#!/bin/sh
# Every check that runs without KOReader. The CI runs tools/check.sh; the release runs tools/check.sh release.
set -eu
cd "$(dirname "$0")/.."
for spec in tests/*_spec.lua; do
    luajit "$spec"
done
luajit tools/check_texts.lua book_rewind/i18n.lua strings:book_rewind/ui/screen.lua strings:book_rewind/ui/card_view.lua \
    'strings():main.lua' book_rewind/share/strings.lua s:book_rewind/share s:book_rewind/ui/share_screen.lua \
    strings:book_rewind/share strings:book_rewind/ui/share_screen.lua
sh tools/package.sh
