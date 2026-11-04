#!/bin/sh
set -eu
: "${KOREADER_DIR:?Set KOREADER_DIR to the KOReader folder, the one with luajit and reader.lua.}"
repo="$(cd "$(dirname "$0")/../.." && pwd)"
home="${KO_HOME:-$repo/.ko-home}"
mkdir -p "$home/plugins" "$home/settings"
ln -sfn "$repo" "$home/plugins/book_rewind.koplugin"
cd "$KOREADER_DIR"
if [ ! -f "$home/settings/statistics.sqlite3" ]; then
    SDL_VIDEODRIVER=dummy KO_HOME="$home" PLUGIN_DIR="$repo" SAMPLE_DB="$home/settings/statistics.sqlite3" \
        ./luajit "$repo/tools/koreader/write_sample.lua" 2>&1 | grep "sample database"
fi
exec env KO_HOME="$home" EMULATE_READER_W=600 EMULATE_READER_H=800 EMULATE_READER_DPI=167 ./luajit reader.lua "$@"
