#!/usr/bin/env python3
"""Regenerate the README screenshots on a USB-connected Boox (adb).

    .venv/bin/python tools/make_sample_epub.py      # samples/xiaoshuo.epub
    tools/deploy.sh                                  # the plugin under test
    .venv/bin/python tools/make_screenshots.py       # all shots -> docs/*.png
    .venv/bin/python tools/make_screenshots.py main  # some of them

Needs the optional dictionaries (CBDB, MOE, 成語典, Xinhua, Moegirlpedia) in
build/ and the same files on the device, and Wi-Fi on (the Translate &
Analyze button shows only while connected). Written for a Boox Go 7 in
landscape (1680x1264): tap positions are screen pixels for the book and
reader settings below.

For every shot, before anything is saved:
  1. The gate (tools/shot_gate.py) runs the page's exact text through the
     plugin's own Lua code: the pinyin it draws must be exactly the shot's
     `drawn` list (each reading checked by hand when the shot was added), and
     each tap's popup must contain the shot's `expect` lines.
  2. On the device, KOReader's log must agree with the gate: the number of
     annotations on the page, and for each tap the context around the
     character and the reading chosen.
Any mismatch stops the script; nothing is written for that shot.

The device's settings.reader.lua is backed up first (build/screenshots/) and
restored at the end, even after an error: the shots use threshold 3,500,
night mode off and debug logging on. The book opens at an xpointer from a
sidecar written here (font, size, margins), so pages and tap positions are
the same on every run. Images are cropped, full width, and saved with 16
grey levels.
"""
import os
import re
import subprocess
import sys
import time
import zipfile
import html

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from shot_gate import Gate, format_popup  # noqa: E402

BOOK = os.path.join(ROOT, "samples", "xiaoshuo.epub")
DEVICE_BOOK = "/sdcard/Download/xiaoshuo.epub"
SIDECAR = "/sdcard/Download/xiaoshuo.sdr/metadata.epub.lua"
SETTINGS = "/sdcard/koreader/settings.reader.lua"
PACKAGE = "org.koreader.launcher"
WORK = os.path.join(ROOT, "build", "screenshots")
BACKUP = os.path.join(WORK, "settings.reader.lua.backup")
DOCS = os.path.join(ROOT, "docs")
THRESHOLD = 3500

READER = {   # the sidecar's reader settings
    "copt_font_size": 20, "copt_line_spacing": 100, "copt_h_page_margins": "{ [1] = 50, [2] = 50 }",
    "copt_t_page_margin": 20, "copt_b_page_margin": 15, "copt_sync_t_b_page_margins": 0,
    "copt_status_line": 1, "copt_embedded_css": 1, "copt_embedded_fonts": 1, "copt_view_mode": 0,
    "copt_visible_pages": 1, "copt_rotation_mode": 0, "copt_word_expansion": 0,
    "copt_word_spacing": "{ [1] = 95, [2] = 75 }", "copt_block_rendering_mode": 3,
    "copt_cjk_width_scaling": 100, "copt_font_base_weight": 0, "copt_font_gamma": 15,
    "copt_font_hinting": 2, "copt_font_kerning": 3, "copt_render_dpi": 96,
    "floating_punctuation": 0, "font_face": '"Noto Serif SC"', "text_lang": '"zh-CN"',
    "cre_dom_version": 20240114,
}

# Pages: chapter (1 三国演义 第一回, 2 孔乙己, 3 阿Q正传), the first and last
# characters on screen, and where to open the book.
PAGES = {
    "sg1": dict(ch=1, first="第一回", last="中涓自此愈横。", xp="/body/DocFragment[1]/body/h1/text().0",
                drawn="樵=qiáo 渚=zhǔ 锢=gù 宦=huàn 涓=juān"),
    "sg2": dict(ch=1, first="建宁二年四月望日", last="能呼风唤雨，号为“太平道", xp="/body/DocFragment[1]/body/p[9]/text().0",
                drawn="蟠=pán 臾=yú 雹=báo 邕=yōng 霓=ní 谞=xū 蹇=jiǎn 恽=yùn 藜=lí 讫=qì"),
    "kyj13": dict(ch=2, first="幸亏荐头的情面大", last="引得众人都哄笑起来；店内外充满",
                  xp="/body/DocFragment[2]/body/p[5]/text().91", drawn="茴=huí"),
    "kyj14": dict(ch=2, first="了快活的空气。", last="我略略点一点头。他",
                  xp="/body/DocFragment[2]/body/p[6]/text().173", drawn="砚=yàn 拭=shì 颓=tuí"),
    "aq59": dict(ch=3, first="“你不知道，他们已经来革过了！”", last="他又退一步想道：",
                 xp="/body/DocFragment[3]/body/p[230]/text().224", drawn="诧=chà 愕=è"),
}

# Shots: the page, the settings, the taps (character, which one on the page,
# screen position, lines the popup must show), then the crop (y0, y1) of each
# frame: frame 0 is the page before any tap, frame k the screen after tap k.
SHOTS = {
    # 密, two thirds into the page's longest sentence: the popup's context
    # line shows text on both sides of it.
    "main": dict(page="sg1", taps=[("密", 1, (172, 1150), [
        "**密**  mì", "**宓** mì  still; silent  → sound (same sound)", "**山** shān  mountain  → meaning",
        "[Wikt]", "**不密**  bùmì", "(literary) not well thought out; (literary) not secret"])],
        frames=[(1, (95, 1185))]),
    "context": dict(page="kyj14", taps=[("间", 1, (773, 500), [
        "**间**  jiàn · likely here", "**间或**  jiànhuò · decides 间's reading"])],
        frames=[(1, (255, 1008))]),
    "components": dict(page="kyj13", taps=[("茴", 1, (988, 790), [
        "**茴**  huí", "**艹** cǎo  grass; plant (草字头)  → meaning",
        "**回** huí  to go back; to return  → sound (same sound)", "**茴香豆**  huíxiāngdòu"])],
        frames=[(1, (247, 1019))]),
    "traditional": dict(page="aq59", taps=[("观", 1, (170, 965), [
        "**观**  guān · likely here", "traditional 觀:", "**雚** guàn", "→ sound (same sound)",
        "simplified: 雚 → 又", "**观音**  Guānyīn · decides 观's reading"])],
        frames=[(1, (220, 1042))]),
    "chengyu": dict(page="kyj13", taps=[("也", 3, (170, 590), [
        "**之乎者也**  zhīhūzhěyě", "[新华] 这四个字都是文言虚词"]), ("出处", None, (1440, 862), [])],
        frames=[(1, (140, 1120)), (2, (20, 700))]),
    "labels": dict(page="sg1", taps=[("秋", 1, (775, 665), [
        "**秋**  qiū", "[MMAH]", "[MOE]", "**秋月春风**  qiū yuè chūn fēng", "[Wikt]", "**秋月**  qiūyuè"])],
        frames=[(1, (127, 1137))]),
    "translate": dict(page="kyj13", taps=[("窃", 1, (1465, 995), ["**窃**  qiè"])],
        frames=[(1, (15, 1160))]),
    # Page 1 with pinyin off, then on: the plugin adds line space where it
    # draws pinyin (69 pages instead of 74), so each crop ends after the same
    # line of text (下。后来光武中兴…), the one with pinyin taller.
    "off-on": dict(page="sg1", taps=[], pinyin_off=True, frames=[(0, (370, 928))], on_crop=(370, 975)),
}


def adb(*args, check=True, binary=False):
    r = subprocess.run(["adb", *args], capture_output=True, check=check)
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


def chapter_text(ch):
    """The chapter's text, one line per block (heading or paragraph)."""
    with zipfile.ZipFile(BOOK) as z:
        x = z.read(f"OEBPS/ch{ch}.xhtml").decode("utf-8")
    body = x[x.index("<body>"):]
    return "\n".join(html.unescape(re.sub(r"<[^>]+>", "", t))
                     for t in re.findall(r"<(?:h1|h2|p)\b[^>]*>(.*?)</(?:h1|h2|p)>", body))


def page_text(page, context=12):
    """The page's text with `context` characters of the text around it marked
    off the page (shot_gate.py's "before|page|after")."""
    text = chapter_text(page["ch"])
    a = text.index(page["first"])
    b = text.index(page["last"], a) + len(page["last"])
    return text[max(0, a - context):a] + "|" + text[a:b] + "|" + text[b:b + context]


def gate_shot(gate, name, shot):
    page = PAGES[shot["page"]]
    text = page_text(page)
    drawn = " ".join(f"{c}={r}" for c, r, _ in gate.annotate(text, THRESHOLD))
    if drawn != page["drawn"]:
        sys.exit(f"{name}: the gate draws\n  {drawn}\nnot the checked\n  {page['drawn']}")
    popups = []
    for char, nth, _, expect in shot["taps"]:
        if nth is None:
            popups.append(None)
            continue
        p = gate.popup(text, THRESHOLD, char, nth)
        shown = format_popup(p)
        missing = [e for e in expect if e not in shown]
        if missing:
            sys.exit(f"{name}: the {char} popup lacks {missing}:\n{shown}")
        popups.append(p)
    print(f"gate ok   {name}: drawn {drawn or 'none'}")
    return popups, len(drawn.split()) if drawn else 0


def settings_variant(original, pinyin=True):
    """The user's settings.reader.lua with the shot settings."""
    keys = {"chinesehelper_threshold": THRESHOLD, "chinesehelper_pinyin_enabled": "true" if pinyin else "false",
            "chinesehelper_popup_enabled": "true", "chinesehelper_popup_text_pct": 60,
            "chinesehelper_labels": '"fallback"', "chinesehelper_uncertain": '"both"',
            "chinesehelper_components": "true", "chinesehelper_popup_context": "true",
            "chinesehelper_page_underline": "true", "night_mode": "false", "autowarmth_control_nightmode": "false",
            "debug": "true"}
    out = original
    for k in keys:
        out = re.sub(rf'(?m)^    \["{k}"\] = [^\n]*\n', "", out)
    head = "".join(f'    ["{k}"] = {v},\n' for k, v in keys.items())
    i = out.index("return {\n") + len("return {\n")
    return out[:i] + head + out[i:]


def sidecar(xp):
    lines = [f'    ["{k}"] = {v},' for k, v in READER.items()]
    lines.append(f'    ["last_xpointer"] = "{xp}",')
    return "return {\n" + "\n".join(lines) + "\n}\n"


def push_text(text, dest):
    path = os.path.join(WORK, "push.tmp")
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    adb("push", path, dest)


def log():
    return adb("logcat", "-d", "-s", "KOReader:*", check=False)


def wait_for(pattern, after, timeout=40):
    """The first log line after `after` lines matching `pattern`."""
    t0 = time.time()
    while time.time() - t0 < timeout:
        lines = log().splitlines()[after:]
        for line in lines:
            m = re.search(pattern, line)
            if m:
                return m
        time.sleep(1)
    sys.exit(f"timed out waiting for /{pattern}/ in KOReader's log")


def screencap():
    path = os.path.join(WORK, "screen.png")
    with open(path, "wb") as f:
        f.write(adb("exec-out", "screencap", "-p", binary=True))
    return Image.open(path).convert("L")


def open_page(shot, original):
    page = PAGES[shot["page"]]
    adb("shell", "am", "force-stop", PACKAGE)
    push_text(settings_variant(original, pinyin=not shot.get("pinyin_off")), SETTINGS)
    adb("shell", "mkdir", "-p", os.path.dirname(SIDECAR))
    push_text(sidecar(page["xp"]), SIDECAR)
    adb("logcat", "-c")
    adb("shell", "am", "start", "-n", f"{PACKAGE}/.MainActivity", "-a", "android.intent.action.VIEW",
        "-d", f'"file://{DEVICE_BOOK}"', "-t", "application/epub+zip")
    if shot.get("pinyin_off"):
        wait_for(r"chinesehelper: reading tables loaded|Plugin loaded chinesehelper", 0)
        time.sleep(6)
        return None
    m = wait_for(r"chinesehelper: page \d+: \d+ items, (\d+) annotated", 0)
    time.sleep(4)   # the second render, and e-ink settling
    return int(m.group(1))


def quantize16(img):
    """16 grey levels, as a palette PNG."""
    levels = img.point(lambda v: min(15, (v + 8) // 17) * 17)
    pal = []
    for k in range(16):
        pal += [k * 17] * 3
    p = Image.new("P", (1, 1))
    p.putpalette(pal + [0] * (768 - len(pal)))
    return levels.convert("RGB").quantize(palette=p, dither=Image.Dither.NONE)


def run_shot(gate, name, shot, original):
    popups, n_drawn = gate_shot(gate, name, shot)
    annotated = open_page(shot, original)
    if annotated is not None and annotated != n_drawn:
        sys.exit(f"{name}: the device annotated {annotated} characters, the gate {n_drawn}")
    frames = [screencap()]
    for (char, nth, pos, _), p in zip(shot["taps"], popups):
        before = len(log().splitlines())
        if p is None:   # a button in the popup (nth None): no log line to check
            adb("shell", "input", "tap", *map(str, pos))
            time.sleep(9)   # a TextViewer takes several seconds to show
        else:
            adb("shell", "input", "tap", *map(str, pos))
            m = wait_for(rf"chinesehelper: {char} \[([^|\]]*)\|([^\]]*)\] reading (\S+),", before)
            header = m.group(1) + "**" + char + "**" + m.group(2)
            if header != p["header"] or m.group(3) != (p["chosen"] or "nil"):
                sys.exit(f"{name}: the device shows {header} reading {m.group(3)}, "
                         f"the gate {p['header']} reading {p['chosen']}")
            time.sleep(3)
        frames.append(screencap())
    raw = os.path.join(WORK, "raw")
    os.makedirs(raw, exist_ok=True)
    variant = "-off" if shot.get("pinyin_off") else ""
    for k, f in enumerate(frames):
        f.save(os.path.join(raw, f"{name}{variant}-{k}.png"))
    return frames


def save(name, img):
    path = os.path.join(DOCS, f"{name}.png")
    quantize16(img).save(path, optimize=True)
    print(f"saved     {os.path.relpath(path, ROOT)} {img.size[0]}x{img.size[1]}")


def crop(img, y):
    return img.crop((0, y[0], img.size[0], y[1]))


def main():
    wanted = sys.argv[1:] or list(SHOTS)
    unknown = [w for w in wanted if w not in SHOTS]
    if unknown:
        sys.exit(f"unknown shots {unknown}; known: {' '.join(SHOTS)}")
    os.makedirs(WORK, exist_ok=True)
    gate = Gate()
    print(f"gate sources: {gate.sources}")
    for name in wanted:   # the whole gate first: no device work if any shot fails it
        gate_shot(gate, name, SHOTS[name])
    if "device" not in adb("get-state", check=False):
        sys.exit("no device")
    # The user's settings: backed up once (a backup left by an interrupted run
    # is the original and is used as is), restored at the end.
    if not os.path.exists(BACKUP):
        adb("shell", "am", "force-stop", PACKAGE)
        adb("pull", SETTINGS, BACKUP)
    with open(BACKUP, encoding="utf-8") as f:
        original = f.read()
    adb("push", BOOK, DEVICE_BOOK)
    try:
        captured = {}
        for name in wanted:
            shot = SHOTS[name]
            captured[name] = run_shot(gate, name, shot, original)
            if name == "off-on":
                # Pinyin off, then on: the same lines, one above the other.
                on = run_shot(gate, name, dict(shot, pinyin_off=False), original)[0]
                off = captured[name][0]
                a, b = crop(off, shot["frames"][0][1]), crop(on, shot["on_crop"])
                both = Image.new("L", (a.size[0], a.size[1] + b.size[1] + 24), 255)
                both.paste(a, (0, 0))
                both.paste(b, (0, a.size[1] + 24))
                for x in range(both.size[0]):
                    both.putpixel((x, a.size[1] + 12), 160)
                save(name, both)
                continue
            for k, (frame, y) in enumerate(shot["frames"]):
                suffix = "" if k == 0 else f"-{k + 1}"
                save(name + suffix, crop(captured[name][frame], y))
    finally:
        adb("shell", "am", "force-stop", PACKAGE)
        adb("push", BACKUP, SETTINGS)
        os.remove(BACKUP)
        adb("shell", "monkey", "-p", PACKAGE, "-c", "android.intent.category.LAUNCHER", "1", check=False)
        print("device settings restored")

if __name__ == "__main__":
    main()
