# CLAUDE.md

## The database

`chinesehelper.koplugin/data/chinesehelper.sqlite` (about 36 MB) is **not in git**; the whole
`chinesehelper.koplugin/data/` folder is gitignored. It is built by `tools/build_db.py` and
shipped inside each GitHub release zip. If it is missing locally and the database hasn't
changed, take it from the latest release zip (`gh release download <tag> -p
chinesehelper.koplugin.zip`) rather than rebuilding.

## Release routine

Every release, after the version bump (`_meta.lua` and `main.lua`) and its `CHANGELOG.md` section
are on `main`:

1. `tools/check.sh` must pass (exit 0).
2. Build the zip from the repo root, into the gitignored `dist/`:
   ```sh
   rm -f dist/chinesehelper.koplugin.zip
   zip -qr -X dist/chinesehelper.koplugin.zip chinesehelper.koplugin -x '*.DS_Store'
   ```
   Check its file list (`unzip -Z1`) against the previous release's asset: the Lua files, the
   two license texts and `data/chinesehelper.sqlite`, nothing else.
3. `gh release create vX.Y.Z dist/chinesehelper.koplugin.zip --title "X.Y.Z: <short summary>"
   --notes-file <notes>`, where the notes are that version's `CHANGELOG.md` section without its
   heading.
4. `tools/deploy.sh` to put the plugin on the Boox over USB (`adb devices` should list it). It
   reruns check.sh, pushes the plugin and restarts KOReader; confirm KOReader is running again
   (`adb shell pidof org.koreader.launcher`).

## Task queue

GitHub issues on scartoon/koreader-chinese-helper are the backlog; all queue state lives there,
not in local files. `/next` (`.claude/commands/next.md`) is the entry point: it resumes the
`in-progress` issue or takes the top open one. Each issue body is the brief for its task (the
**Brief** template: Goal, Context, Steps, Done when, Stop and ask if); later comments from Simon
override the body.

- `P1`, `P2`, `P3`: priority, P1 most urgent; unlabelled goes last. Within a label, lowest issue
  number first.
- `in-progress`: the item currently being worked on (at most one).
- `needs-simon`: blocked on a question or decision from Simon; /next skips it.
- `draft`: a quick capture, not yet a full brief; /next skips it.
- An issue whose body says "Depends on #X" waits until #X is closed.
