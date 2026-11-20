#!/bin/sh
# Creates the fake reading history used by tools/koreader/run_emulator.sh, once: a later run keeps it.
# Called by run_emulator.sh with KOREADER_DIR, KO_HOME and PLUGIN_DIR set.
set -eu
db="$KO_HOME/settings/statistics.sqlite3"
[ -f "$db" ] && exit 0
mkdir -p "$KO_HOME/settings"
cd "$KOREADER_DIR"
SDL_VIDEODRIVER=dummy KO_HOME="$KO_HOME" PLUGIN_DIR="$PLUGIN_DIR" SAMPLE_DB="$db" \
    ./luajit "$PLUGIN_DIR/tools/koreader/write_sample.lua" 2>&1 | grep "sample database"
