#!/bin/sh
# Syntax-check every Lua file and run the offline tests. Run before every push
# to a device: a syntax error in any file takes the whole plugin down.
#     tools/check.sh            (uses .venv/bin/python when present)
set -e
cd "$(dirname "$0")/.."
PY=python3
[ -x .venv/bin/python ] && PY=.venv/bin/python
status=0
for f in $(find chinesehelper.koplugin tests -name '*.lua'); do
    luac -p "$f" || status=1
    # LuaJIT is what KOReader runs; it rejects some 5.4-only syntax luac accepts.
    if command -v luajit >/dev/null; then luajit -b "$f" /dev/null || status=1; fi
done
[ $status -eq 0 ] && echo "syntax ok"
# The Status screen's version (main.lua) must match the plugin metadata.
meta=$(sed -n 's/.*version = "\(.*\)".*/\1/p' chinesehelper.koplugin/_meta.lua)
main=$(sed -n 's/^ChineseHelper.VERSION = "\(.*\)"/\1/p' chinesehelper.koplugin/main.lua)
if [ "$meta" != "$main" ]; then echo "version mismatch: _meta.lua $meta, main.lua $main"; status=1; else echo "version $meta"; fi
"$PY" tests/run.py || status=1
# The build's Python unit tests (the simplified-text converter needs OpenCC).
if "$PY" -c "import opencc" 2>/dev/null; then
    "$PY" -m unittest discover -s tests -p 'test_*.py' || status=1
else
    echo "python tests skipped: pip install opencc"; status=1
fi
exit $status
