#!/usr/bin/env python3
"""Regenerate the README screenshots on a USB-connected Boox (adb).

    .venv/bin/python tools/make_sample_epub.py      # samples/xiaoshuo.epub
    tools/deploy.sh                                  # the plugin under test
    .venv/bin/python tools/make_screenshots.py       # all shots -> docs/*.png
    .venv/bin/python tools/make_screenshots.py main  # some of them
    .venv/bin/python tools/make_screenshots.py translate-result   # opt-in only

translate-result (KOAssistant's reply to Translate & Analyze) is never part of
a default run: the AI's answer varies, so it can't be gated like the others.

For checks, not the README: SHOT_FONT="STKaiti" uses another book font (taps
must still land: the device log is checked as usual), SHOT_MATCH_FONT=false
turns "Try to match the book's font" off, and SHOT_OUT=dir saves there
instead of docs/.

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

The device's settings.reader.lua and reading marks are backed up first
(build/screenshots/) and restored at the end, even after an error: the shots
use threshold 3,500 (the learner shots All), no marks (learner-known the
LEARNER_KNOWN readings), night mode off and debug logging on. The book opens at an xpointer from a
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
DOCS = os.environ.get("SHOT_OUT") or os.path.join(ROOT, "docs")
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
if os.environ.get("SHOT_FONT"):
    READER["font_face"] = '"%s"' % os.environ["SHOT_FONT"]

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

# Learner mode (#25): page aq59 with pinyin on every character (threshold 0).
# Every reading hand-checked; the one pair, 革过 guò/guo, has the right
# reading (guo, the aspect particle) second.
AQ59_ALL = (
    "你=nǐ 不=bù 知=zhī 道=dào 他=tā 们=men 已=yǐ 经=jīng 来=lái 革=gé 过=guò/guo 了=le 谁=shéi 阿=ā 更=gèng "
    "其=qí 诧=chà 异=yì 了=le 那=nà 秀=xiù 才=cái 和=hé 洋=yáng 鬼=guǐ 子=zi 阿=ā 很=hěn 出=chū 意=yì 外=wài "
    "不=bù 由=yóu 的=de 一=yī 错=cuò 愕=è 老=lǎo 尼=ní 姑=gū 见=jiàn 他=tā 失=shī 了=le 锐=ruì 气=qì 便=biàn "
    "飞=fēi 速=sù 的=de 关=guān 了=le 门=mén 阿=ā 再=zài 推=tuī 时=shí 牢=láo 不=bù 可=kě 开=kāi 再=zài 打=dǎ "
    "时=shí 没=méi 有=yǒu 回=huí 答=dá 了=le 那=nà 还=hái 是=shi 上=shàng 午=wǔ 的=de 事=shì 赵=zhào 秀=xiù "
    "才=cái 消=xiāo 息=xī 灵=líng 一=yī 知=zhī 道=dào 革=gé 命=mìng 党=dǎng 已=yǐ 在=zài 夜=yè 间=jiān "
    "进=jìn 城=chéng 便=biàn 将=jiāng 辫=biàn 子=zi 盘=pán 在=zài 顶=dǐng 上=shàng 一=yī 早=zǎo 去=qù "
    "拜=bài 访=fǎng 那=nà 历=lì 来=lái 也=yě 不=bù 相=xiāng 能=néng 的=de 钱=qián 洋=yáng 鬼=guǐ 子=zi "
    "这=zhè 是=shì 咸=xián 与=yù 维=wéi 新=xīn 的=de 时=shí 候=hòu 了=le 所=suǒ 以=yǐ 他=tā 们=men 便=biàn "
    "谈=tán 得=de 很=hěn 投=tóu 机=jī 立=lì 刻=kè 成=chéng 了=le 情=qíng 投=tóu 意=yì 合=hé 的=de 同=tóng "
    "志=zhì 也=yě 相=xiāng 约=yuē 去=qù 革=gé 命=mìng 他=tā 们=men 想=xiǎng 而=ér 又=yòu 想=xiǎng 才=cái "
    "想=xiǎng 出=chū 静=jìng 修=xiū 庵=ān 里=lǐ 有=yǒu 一=yī 块=kuài 皇=huáng 帝=dì 万=wàn 岁=suì 万=wàn "
    "万=wàn 岁=suì 的=de 龙=lóng 牌=pái 是=shì 应=yīng 该=gāi 赶=gǎn 紧=jǐn 革=gé 掉=diào 的=de 于=yú 是=shì "
    "又=yòu 立=lì 刻=kè 同=tóng 到=dào 庵=ān 里=lǐ 去=qù 革=gé 命=mìng 因=yīn 为=wèi 老=lǎo 尼=ní 姑=gū "
    "来=lái 阻=zǔ 挡=dǎng 说=shuō 了=le 三=sān 句=jù 话=huà 他=tā 们=men 便=biàn 将=jiāng 伊=yī 当=dàng "
    "作=zuò 满=mǎn 政=zhèng 府=fǔ 在=zài 头=tóu 上=shàng 很=hěn 给=gěi 了=le 不=bù 少=shǎo 的=de 棍=gùn "
    "子=zi 和=hé 栗=lì 凿=záo 尼=ní 姑=gū 待=dài 他=tā 们=men 走=zǒu 后=hòu 定=dìng 了=le 神=shén 来=lái "
    "检=jiǎn 点=diǎn 龙=lóng 牌=pái 固=gù 然=rán 已=yǐ 经=jīng 碎=suì 在=zài 地=dì 上=shang 了=le 而=ér "
    "且=qiě 又=yòu 不=bù 见=jiàn 了=le 观=guān 音=yīn 娘=niáng 娘=niang 座=zuò 前=qián 的=de 一=yī 个=ge "
    "宣=xuān 德=dé 炉=lú 这=zhè 事=shì 阿=ā 后=hòu 来=lái 才=cái 知=zhī 道=dào 他=tā 颇=pō 悔=huǐ 自=zì 己=jǐ "
    "睡=shuì 着=zháo 但=dàn 也=yě 深=shēn 怪=guài 他=tā 们=men 不=bù 来=lái 招=zhāo 呼=hū 他=tā 他=tā 又=yòu "
    "退=tuì 一=yī 步=bù 想=xiǎng 道=dào ").strip()
# learner-known: the page after a beginner has marked known the 80 commonest
# characters on it (by 字频 rank, up to 271), each in its default reading,
# so 是 shi in 还是 keeps its pinyin. Pushed as the device's marks file.
LEARNER_KNOWN = [tuple(k.split("=")) for k in (
    "的=de 是=shì 一=yī 在=zài 不=bù 有=yǒu 了=le 这=zhè 们=men 他=tā 来=lái 和=hé 上=shàng 以=yǐ 到=dào "
    "时=shí 能=néng 你=nǐ 可=kě 地=dì 出=chū 也=yě 说=shuō 于=yú 后=hòu 成=chéng 自=zì 没=méi 作=zuò 得=de "
    "开=kāi 经=jīng 还=hái 而=ér 事=shì 里=lǐ 政=zhèng 所=suǒ 新=xīn 同=tóng 定=dìng 其=qí 进=jìn 前=qián "
    "机=jī 那=nà 关=guān 但=dàn 因=yīn 道=dào 去=qù 很=hěn 间=jiān 然=rán 想=xiǎng 点=diǎn 将=jiāng 意=yì "
    "合=hé 三=sān 外=wài 由=yóu 已=yǐ 情=qíng 应=yīng 相=xiāng 给=gěi 该=gāi 立=lì 知=zhī 更=gèng 话=huà "
    "己=jǐ 回=huí 见=jiàn 府=fǔ 少=shǎo 又=yòu 老=lǎo 万=wàn ").split()]

# Shots: the page, the settings, the taps (character, which one on the page,
# screen position, lines the popup must show; or "nested" for a character in
# the popup's text, and the sentence the device must log for it), then the crop (y0, y1) of each
# frame: frame 0 is the page before any tap, frame k the screen after tap k.
SHOTS = {
    # 密, two thirds into the page's longest sentence: the popup's context
    # line shows text on both sides of it.
    "main": dict(page="sg1", taps=[("密", 1, (172, 1150), [
        "**密**  mì", "[MOE] Always\n  **密**  mì", "**宓** mì  still; silent  → sound (same sound)", "**山** shān  mountain  → meaning",
        "[Wikt]", "**不密**  bùmì", "(literary) not well thought out; (literary) not secret"])],
        frames=[(1, (117, 1185))]),
    "context": dict(page="kyj14", taps=[("间", 1, (773, 500), [
        "**间**  jiàn · likely here", "[MOE] Always\n  **间**  jiàn", "**间或**  jiànhuò · decides 间's reading"])],
        frames=[(1, (95, 1167))]),
    "components": dict(page="kyj13", taps=[("茴", 1, (988, 790), [
        "**茴**  huí", "[MOE] Always\n  **茴**  huí", "**艹** cǎo  grass; plant (草字头)  → meaning",
        "**回** huí  to go back; to return  → sound (same sound)", "**茴香豆**  huíxiāngdòu"])],
        frames=[(1, (108, 1155))]),
    "traditional": dict(page="aq59", taps=[("观", 1, (170, 965), [
        "**观**  guān · likely here", "[MOE] Always\n  **观**  guān", "traditional 觀:", "**雚** guàn", "→ sound (same sound)",
        "simplified: 雚 → 又", "**观音**  Guānyīn · decides 观's reading"])],
        frames=[(1, (61, 1201))]),
    "chengyu": dict(page="kyj13", taps=[("也", 3, (170, 590), [
        "[MOE] Always\n  **也**  yě", "**之乎者也**  zhīhūzhěyě", "[新华] 这四个字都是文言虚词"]), ("出处", None, (1440, 980), [])],
        frames=[(1, (28, 1235)), (2, (20, 700))]),
    "labels": dict(page="sg1", taps=[("秋", 1, (775, 665), [
        "**秋**  qiū", "[MOE] Always\n  **秋**  qiū", "[MMAH]", "  [MOE]\n  **秋月春风**", "**秋月春风**  qiū yuè chūn fēng", "[Wikt]", "**秋月**  qiūyuè"])],
        frames=[(1, (18, 1245))]),
    # A character of the popup's own text: 欢, inside MOE's quotation of 〈琵琶行〉,
    # opens its popup on top; the context line is the quotation (the device's
    # log must give it as the sentence), the 欢 below underlined.
    "nested": dict(page="sg1", taps=[("秋", 1, (775, 665), ["[MOE] Always\n  **秋**  qiū", "  [MOE]\n  **秋月春风**  qiū yuè chūn fēng"]),
                                     ("欢", "nested", (1322, 872), ["「今年欢笑复明年，秋月春风等闲度。」"])],
                   frames=[(2, (18, 1245))]),
    "translate": dict(page="kyj13", taps=[("窃", 1, (1465, 995), ["**窃**  qiè", "[MOE] Always\n  **窃**  qiè"])],
        frames=[(1, (15, 1160))]),
    # The same popup, then its Translate & Analyze button (at `koassistant`):
    # KOAssistant's reply, its viewer unrolled: the first page, then the last
    # page's text and buttons (`koassistant_end` is the viewer's ↘ button),
    # joined by a dashed line (see reply_image). Opt-in only (OPT_IN): the
    # AI's answer differs from run to run, so nothing can check it the way the
    # gate checks the other shots, and a default run would silently replace an
    # image whose README alt text describes one particular answer. Take it by
    # name, look at it, and rewrite the alt text to match.
    "translate-result": dict(page="kyj13", taps=[("窃", 1, (1465, 995), ["**窃**  qiè"])],
        koassistant=(840, 920), koassistant_end=(1245, 1195)),
    # Page 1 with pinyin off, then on: the plugin adds line space where it
    # draws pinyin (69 pages instead of 74), so each crop ends after the same
    # line of text (下。后来光武中兴…), the one with pinyin taller.
    "off-on": dict(page="sg1", taps=[], pinyin_off=True, frames=[(0, (370, 928))], on_crop=(370, 975)),
    # Learner mode (#25): the same paragraph of 阿Q正传 with pinyin on every
    # character, then after the 80 commonest readings on the page are known.
    "learner": dict(page="aq59", threshold=0, drawn=AQ59_ALL, taps=[], frames=[(0, (440, 995))]),
    "learner-known": dict(page="aq59", threshold=0, known=LEARNER_KNOWN, taps=[], frames=[(0, (440, 995))]),
    # The popup's title-bar button, on 盘 in that paragraph.
    "mark-button": dict(page="aq59", threshold=0, drawn=AQ59_ALL, taps=[("盘", 1, (260, 565), ["**盘**  pán"])],
                        frames=[(1, (193, 555))]),
}


OPT_IN = {"translate-result"}   # never in a default run; see its SHOTS entry

KOA_CHATS = "/sdcard/Download/xiaoshuo.sdr/koassistant_chats.lua"
MARKS = "/sdcard/koreader/settings/chinesehelper_marks.lua"
MARKS_BACKUP = os.path.join(WORK, "chinesehelper_marks.lua.backup")


def expected_drawn(shot):
    """The shot's hand-checked pinyin: its own list, or its page's at 3,500;
    known readings (shot["known"]) taken out of the page's All list."""
    if shot.get("known"):
        known = {f"{c}={r}" for c, r in shot["known"]}
        return " ".join(a for a in AQ59_ALL.split() if a not in known)
    return shot.get("drawn") or PAGES[shot["page"]]["drawn"]


def marks_file(known):
    """The device's marks file holding `known` as known readings (none: empty)."""
    rows = {}
    for c, r in known or ():
        rows.setdefault(c, []).append(f'["{r}"] = "known"')
    body = "".join(f'        ["{c}"] = {{ {", ".join(v)} }},\n' for c, v in rows.items())
    return "return {\n    version = 1,\n    marks = {\n" + body + "    },\n}\n"


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
    threshold = shot.get("threshold", THRESHOLD)
    drawn = " ".join(f"{c}={r}" for c, r, _ in gate.annotate(text, threshold, known=shot.get("known", ())))
    if drawn != expected_drawn(shot):
        sys.exit(f"{name}: the gate draws\n  {drawn}\nnot the checked\n  {expected_drawn(shot)}")
    popups = []
    for char, nth, _, expect in shot["taps"]:
        if nth is None or nth == "nested":
            popups.append(None)
            continue
        p = gate.popup(text, threshold, char, nth)
        shown = format_popup(p)
        missing = [e for e in expect if e not in shown]
        if missing:
            sys.exit(f"{name}: the {char} popup lacks {missing}:\n{shown}")
        popups.append(p)
    print(f"gate ok   {name}: drawn {drawn or 'none'}")
    return popups, len(drawn.split()) if drawn else 0


def settings_variant(original, pinyin=True, threshold=None):
    """The user's settings.reader.lua with the shot settings."""
    keys = {"chinesehelper_threshold": THRESHOLD if threshold is None else threshold, "chinesehelper_pinyin_enabled": "true" if pinyin else "false",
            "chinesehelper_popup_enabled": "true", "chinesehelper_popup_text_pct": 60,
            "chinesehelper_chinese_text_pct": 130, "chinesehelper_char_rank": "true",
            "chinesehelper_labels": '"fallback"', "chinesehelper_uncertain": '"both"',
            "chinesehelper_components": "true", "chinesehelper_popup_context": "true",
            "chinesehelper_page_underline": "true",
            "chinesehelper_match_book_font": "false" if os.environ.get("SHOT_MATCH_FONT") == "false" else "true",
            "night_mode": "false", "autowarmth_control_nightmode": "false",
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
    push_text(settings_variant(original, pinyin=not shot.get("pinyin_off"), threshold=shot.get("threshold")), SETTINGS)
    push_text(marks_file(shot.get("known")), MARKS)
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
    for (char, nth, pos, expect), p in zip(shot["taps"], popups):
        before = len(log().splitlines())
        if nth == "nested":   # a character in the popup's text: its sentence is checked
            adb("shell", "input", "tap", *map(str, pos))
            m = wait_for(rf'chinesehelper: nested {char} \[[^]]*\] depth \d+, sentence "([^"]*)"', before)
            if m.group(1) != expect[0]:
                sys.exit(f"{name}: the nested {char} popup's sentence is {m.group(1)}, not {expect[0]}")
            time.sleep(3)
        elif p is None:   # a button in the popup (nth None): no log line to check
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
    if shot.get("koassistant"):
        frames.append(koassistant_reply(name, shot["koassistant"]))
        adb("shell", "input", "tap", *map(str, shot["koassistant_end"]))
        time.sleep(4)
        frames.append(screencap())
    raw = os.path.join(WORK, "raw")
    os.makedirs(raw, exist_ok=True)
    variant = "-off" if shot.get("pinyin_off") else ""
    for k, f in enumerate(frames):
        f.save(os.path.join(raw, f"{name}{variant}-{k}.png"))
    return frames


def koassistant_reply(name, pos):
    """Tap the popup's Translate & Analyze button and wait for KOAssistant's
    reply to be complete: the viewer shows it (its "exchange page break" log
    line), then the chat is auto-saved. A timeout or an error line stops the
    script, never a capture of a reply still arriving."""
    before = len(log().splitlines())
    adb("shell", "input", "tap", *map(str, pos))
    wait_for(r"KOAssistant: Executing quick action - Translate & Analyze", before, timeout=10)
    m = wait_for(r"KOAssistant: (exchange page break|Auto-saved chat|.*[Ee]rror.*)", before, timeout=120)
    if "rror" in m.group(1):
        sys.exit(f"{name}: KOAssistant logged {m.group(0)}")
    wait_for(r"KOAssistant: Auto-saved chat", before, timeout=15)
    time.sleep(5)   # e-ink settling
    img = screencap()
    # The reply's text, for the README alt text (the newest chat in the
    # sample book's sidecar).
    path = os.path.join(WORK, "koassistant_chats.lua")
    adb("pull", KOA_CHATS, path)
    with open(path, encoding="utf-8", errors="replace") as f:
        replies = re.findall(r'\["content"\] = "((?:[^"\\]|\\.|\\\n)*)"', f.read())
    os.remove(path)
    if replies:
        text = replies[-1].replace("\\\n", "\n").replace('\\"', '"')
        with open(os.path.join(WORK, f"{name}.txt"), "w", encoding="utf-8") as f:
            f.write(text + "\n")
        print(f"reply     {name} (build/screenshots/{name}.txt):\n{text}")
    return img


# KOAssistant's viewer (full screen): the text area and its scrollbar, the
# button rows below it.
KOA_TEXT = (130, 1035)     # rows of the text area, below the title bar
KOA_BUTTONS = 1040         # from here down: the two button rows and the border
KOA_THUMB_X = 1631         # a column inside the scrollbar's thumb
KOA_FRAME = (8, 1258)      # the viewer's outer border


def thumb(img):
    """First and last row of the scrollbar's thumb."""
    runs, start = [], None   # the longest dark run (the track's ends are dark too)
    for y in range(*KOA_TEXT):
        dark = img.getpixel((KOA_THUMB_X, y)) < 80
        if dark and start is None:
            start = y
        elif not dark and start is not None:
            runs.append((start, y - 1))
            start = None
    if start is not None:
        runs.append((start, KOA_TEXT[1] - 1))
    return max(runs, key=lambda r: r[1] - r[0])


def reply_image(name, first, last):
    """The whole reply in one image: the viewer's first page, then the last
    page's text (trimmed after its last line) and the buttons. Only for a reply
    of one or two pages: the last page's thumb must start where the first
    page's ends, or a middle page would be missing and the script stops."""
    t1, t2 = thumb(first), thumb(last)
    if t1[1] >= KOA_TEXT[1] - 20:   # one page: the whole reply is on it
        return crop(first, KOA_FRAME)
    if t2[0] > t1[1] + 4:
        sys.exit(f"{name}: the reply runs past two pages (scrollbar {t1}, then {t2}); take it again")
    ink = [y for y in range(KOA_TEXT[0], KOA_BUTTONS)
           if any(last.getpixel((x, y)) < 100 for x in range(40, 1600, 2))]
    parts = [crop(first, (KOA_FRAME[0], KOA_TEXT[1])),
             crop(last, (KOA_TEXT[0], min(ink[-1] + 45, KOA_BUTTONS))),
             crop(last, (KOA_BUTTONS, KOA_FRAME[1]))]
    gap = 30   # the join between the pages: white, with a dashed line
    out = Image.new("L", (first.size[0], sum(p.size[1] for p in parts) + gap), 255)
    out.paste(parts[0], (0, 0))
    y = parts[0].size[1]
    for x in range(0, out.size[0], 24):
        for dx in range(12):
            if x + dx < out.size[0]:
                out.putpixel((x + dx, y + gap // 2), 120)
    y += gap
    for p in parts[1:]:
        out.paste(p, (0, y))
        y += p.size[1]
    return out


def save(name, img):
    path = os.path.join(DOCS, f"{name}.png")
    quantize16(img).save(path, optimize=True)
    print(f"saved     {os.path.relpath(path, ROOT)} {img.size[0]}x{img.size[1]}")


def crop(img, y):
    return img.crop((0, y[0], img.size[0], y[1]))


def main():
    wanted = sys.argv[1:] or [s for s in SHOTS if s not in OPT_IN]
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
    # The reading marks too: every shot runs with its own (none, or `known`).
    if not os.path.exists(MARKS_BACKUP):
        adb("pull", MARKS, MARKS_BACKUP, check=False)
    marks_existed = os.path.exists(MARKS_BACKUP)
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
            if shot.get("koassistant"):
                save(name, reply_image(name, *captured[name][-2:]))
                continue
            for k, (frame, y) in enumerate(shot["frames"]):
                suffix = "" if k == 0 else f"-{k + 1}"
                save(name + suffix, crop(captured[name][frame], y))
    finally:
        adb("shell", "am", "force-stop", PACKAGE)
        adb("push", BACKUP, SETTINGS)
        os.remove(BACKUP)
        if marks_existed:
            adb("push", MARKS_BACKUP, MARKS)
            os.remove(MARKS_BACKUP)
        else:
            adb("shell", "rm", "-f", MARKS)
        adb("shell", "monkey", "-p", PACKAGE, "-c", "android.intent.category.LAUNCHER", "1", check=False)
        print("device settings restored")

if __name__ == "__main__":
    main()
