#!/bin/sh
# Check, push the plugin to a USB-connected Android device and restart KOReader.
#     tools/deploy.sh ["/sdcard/Books/some book.epub"]
# Needs the database: tools/build_db.py first.
set -e
cd "$(dirname "$0")/.."
tools/check.sh
DEST=/sdcard/koreader/plugins
[ -f chinesehelper.koplugin/data/chinesehelper.sqlite ] || { echo "no database: run tools/build_db.py"; exit 1; }
adb shell rm -rf "$DEST/chinesehelper.koplugin"
adb push chinesehelper.koplugin "$DEST/" >/dev/null
adb shell am force-stop org.koreader.launcher
if [ -n "$1" ]; then
    adb shell am start -n org.koreader.launcher/.MainActivity -a android.intent.action.VIEW \
        -d "\"file://$1\"" -t application/epub+zip >/dev/null
else
    adb shell monkey -p org.koreader.launcher -c android.intent.category.LAUNCHER 1 >/dev/null
fi
echo "pushed and restarted"
