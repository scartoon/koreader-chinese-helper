#!/usr/bin/env python3
"""Verify neutral-tone candidates by web lookup (#60, phase 3).

Decision rule (agreed with Simon): candidates from the 普通话水平测试 must-read
list (source A) are approved without a lookup. Every other candidate in
docs/neutral-tone-candidates.tsv is approved only when a web lookup finds
written evidence that mainland Standard Mandarin reads that syllable neutral:
a 现代汉语词典-style entry with the dot before the syllable (pēn·tì and pēn·ti
both count) or an explicit 轻声 note. Taiwan/MOE sources count neither way. No
evidence keeps CC-CEDICT's reading: a miss is fine, a wrong change is not.

One request per word: Claude Sonnet 5.5 with the server-side web search tool
(at most MAX_SEARCHES searches) and a JSON-schema answer. A "neutral" verdict
is then checked mechanically (check()): it needs an http(s) URL that is not a
Taiwan site and a snippet with "·" right before the syllable's letters, or
"轻声"; otherwise it counts as no evidence. Answers are cached per word in
docs/neutral-tone-lookups.jsonl, so a rerun never repeats a lookup.

    tools/verify_neutral_tones.py --estimate          # counts and estimated cost, no requests
    ANTHROPIC_API_KEY=... tools/verify_neutral_tones.py --limit 5    # a pilot
    ANTHROPIC_API_KEY=... tools/verify_neutral_tones.py              # everything not cached
    tools/verify_neutral_tones.py --write             # evidence TSV + override file, no requests

Progress goes to build/neutral/verify.log.

--baidu (#64): no model and no web search. For each candidate whose main
Wiktionary reading has the neutral syllable, fetch Baidu Hanyu's JSON
(hanyu.baidu.com/hanyu/ajax/search_list, the data behind dict.baidu.com; the
page itself is rendered by JavaScript), one request at a time with a pause,
raw answers cached in build/neutral/baidu/<word>.json. Baidu gives several
pinyin lines per word; the 现代汉语词典 ones keep its dot (蹊跷 qī·qiao,
进去 jìn·qù). Verdict per word (baidu_verdict()): "neutral" when a line has
the dot before every neutral syllable (or a definition notes 轻声); "not
neutral" when the word is there with a full tone and no dot; "both readings"
when a dotted line sits next to a full-tone line with 现汉-style wording, i.e. a
separate full-tone sense (大大 dà dà "greatly" / dà·da "uncle"), not approved;
"no evidence"
when the word is missing or only a toneless line without the dot (Baidu's
non-现汉 lines: 男人 nán ren, 劳动 láo dong) speaks for it; "fetch failed".
Results go to the same lookups cache with "method": "baidu".

    tools/verify_neutral_tones.py --baidu --limit 10  # a pilot
    tools/verify_neutral_tones.py --baidu             # every main-reading candidate not cached

--haiku-search (#64): the default web-search lookup with Claude Haiku 5.5, for
the main-reading candidates Baidu could not answer (its captcha); any mainland
source, same check().

--haiku (#64): the same Baidu JSON and the same baidu_verdict(), but fetched
through Claude Haiku 5.5's server-side web fetch tool, because Baidu shows its
captcha to direct scripted requests after about 20. The model only triggers
the fetch; the raw JSON is read from the web_fetch_tool_result block and judged
mechanically. Cached like --baidu, with "method": "haiku".

    ANTHROPIC_API_KEY=... tools/verify_neutral_tones.py --haiku --limit 5
"""
import argparse
import json
import os
import re
import sys
import threading
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pinyin_util import is_toneless, numbered_to_marked, strip_tone  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CANDIDATES = os.path.join(ROOT, "docs", "neutral-tone-candidates.tsv")
CACHE = os.path.join(ROOT, "docs", "neutral-tone-lookups.jsonl")
EVIDENCE = os.path.join(ROOT, "docs", "neutral-tone-evidence.tsv")
OVERRIDES = os.path.join(ROOT, "data", "neutral_tone_overrides.tsv")
LOG = os.path.join(ROOT, "build", "neutral", "verify.log")
BAIDU_RAW = os.path.join(ROOT, "build", "neutral", "baidu")
BAIDU_API = "https://hanyu.baidu.com/hanyu/ajax/search_list?"
BAIDU_PAGE = "https://dict.baidu.com/s?wd="
BAIDU_UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/130.0 Safari/537.36")
BAIDU_PAUSE = float(os.environ.get("BAIDU_PAUSE", "2.0"))   # seconds between requests

HAIKU = "claude-haiku-5-5"
HAIKU_PRICE_IN, HAIKU_PRICE_OUT = 0.10 / 1e6, 0.50 / 1e6
MODEL = "claude-sonnet-5-5"
MAX_SEARCHES = 3
# USD, for the estimate: Sonnet 5.5 per million tokens, web search per search.
PRICE_IN, PRICE_OUT, PRICE_SEARCH = 2.00 / 1e6, 10.00 / 1e6, 10.00 / 1000
# Before a pilot has measured it: a guess per lookup.
GUESS_IN, GUESS_OUT, GUESS_SEARCHES = 25000, 1500, 2.5

SCHEMA = {
    "type": "object",
    "properties": {
        "verdict": {"type": "string", "enum": ["neutral", "not neutral", "no evidence"]},
        "syllable": {"type": "string", "description": "the syllable the evidence is about, in pinyin"},
        "url": {"type": "string"},
        "snippet": {"type": "string", "description": "verbatim text from the page, with the dot or 轻声 note"},
        "note": {"type": "string"},
    },
    "required": ["verdict", "syllable", "url", "snippet", "note"],
    "additionalProperties": False,
}

PROMPT = """I maintain a Chinese reading aid that shows pinyin. CC-CEDICT gives the word {word} the reading {cedict}. Another source says mainland Standard Mandarin (普通话) reads it {proposed}, with the syllable {syl} ({char}) in the neutral tone (轻声).

Search the web for written evidence about how mainland Standard Mandarin reads {word}. What counts as evidence:
- a 现代汉语词典 (or 新华词典 or another mainland standard dictionary) entry, or a page quoting one, whose pinyin has the dot before that syllable: e.g. "{dotted}" or the same with a tone mark after the dot (a dot before a toned syllable means "usually neutral, sometimes stressed", which also counts as neutral);
- or an explicit note that the syllable {syl} in {word} is read 轻声.
Taiwan sources (教育部重編國語辭典, dict.revised.moe.edu.tw, any .tw site) do not count either way. Pinyin input tools, machine-generated pinyin pages and plain pinyin without a dot do not count.

Answer with:
- verdict: "neutral" only with evidence as above; "not neutral" if a mainland standard dictionary gives the syllable a full tone with no dot; otherwise "no evidence";
- syllable: the syllable the evidence is about;
- url: the page the evidence is on;
- snippet: a short verbatim quote from that page showing the dot or the 轻声 note (copy it exactly, including the "·");
- note: one short sentence.
If unsure, answer "no evidence"."""

lock = threading.Lock()


def log(msg):
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with lock, open(LOG, "a", encoding="utf-8") as f:
        f.write(time.strftime("%H:%M:%S ") + msg + "\n")


def read_candidates():
    rows = []
    with open(CANDIDATES, encoding="utf-8") as f:
        header = next(f).rstrip("\n").split("\t")
        for line in f:
            rows.append(dict(zip(header, line.rstrip("\n").split("\t"))))
    return rows


def neutral_positions(row):
    c, p = row["cedict"].split(), row["proposed"].split()
    return [k for k in range(len(c)) if c[k] != p[k]]


def read_cache():
    out = {}
    if os.path.exists(CACHE):
        with open(CACHE, encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    d = json.loads(line)
                    out[d["word"]] = d
    return out


def marked(numbered):
    return " ".join(numbered_to_marked(s) for s in numbered.split())


def check(row, answer):
    """The verdict after the mechanical check: "neutral" only with a URL
    (not Taiwan) and a snippet that has "·" before the syllable's letters, or
    轻声; any other "neutral" becomes "no evidence"."""
    if answer.get("verdict") != "neutral":
        return answer.get("verdict") or "no evidence"
    url, snippet = answer.get("url", ""), answer.get("snippet", "")
    if not re.match(r"https?://", url) or re.search(r"\.tw(/|$|:)|moe\.edu", url):
        return "no evidence"
    letters = [strip_tone(numbered_to_marked(row["proposed"].split()[k])) for k in neutral_positions(row)]
    plain = strip_tone(snippet.lower()).replace(" ", "")
    if "轻声" in snippet or "輕聲" in snippet:
        return "neutral" if row["word"] in snippet or any(l in plain for l in letters) else "no evidence"
    if all(re.search(r"[·•‧・]" + re.escape(l) + r"(?![a-z])", plain) for l in letters):
        return "neutral"
    return "no evidence"


def lookup(client, row, model=MODEL):
    k = neutral_positions(row)[0]
    proposed_m, cedict_m = marked(row["proposed"]), marked(row["cedict"])
    syls = proposed_m.split()
    dotted = "".join(s if i == 0 else ("·" + s if i in neutral_positions(row) else s) for i, s in enumerate(syls))
    prompt = PROMPT.format(word=row["word"], cedict=cedict_m.replace(" ", ""), proposed=proposed_m.replace(" ", ""),
                           syl=syls[k], char=row["word"][k], dotted=dotted)
    messages = [{"role": "user", "content": prompt}]
    usage = {"input": 0, "output": 0, "searches": 0}
    for _ in range(4):   # pause_turn: resend to let the server continue
        if model == HAIKU:   # basic search tool; Haiku has no server-side fallback
            msg = client.messages.create(
                model=model, max_tokens=16000, messages=messages,
                tools=[{"type": "web_search_20250305", "name": "web_search", "max_uses": MAX_SEARCHES}],
                output_config={"effort": "low", "format": {"type": "json_schema", "schema": SCHEMA}},
            )
        else:
            msg = client.beta.messages.create(
                model=model, max_tokens=16000, messages=messages,
                tools=[{"type": "web_search_20260209", "name": "web_search", "max_uses": MAX_SEARCHES}],
                output_config={"effort": "low", "format": {"type": "json_schema", "schema": SCHEMA}},
                betas=["server-side-fallback-2026-07-01"], fallbacks="default",
            )
        usage["input"] += msg.usage.input_tokens + (msg.usage.cache_read_input_tokens or 0) + \
            (msg.usage.cache_creation_input_tokens or 0)
        usage["output"] += msg.usage.output_tokens
        stu = getattr(msg.usage, "server_tool_use", None)
        usage["searches"] += (getattr(stu, "web_search_requests", 0) or 0) if stu else 0
        if msg.stop_reason == "pause_turn":
            messages = [messages[0], {"role": "assistant", "content": msg.content}]
            continue
        break
    if msg.stop_reason == "refusal":
        answer = {"verdict": "no evidence", "syllable": "", "url": "", "snippet": "", "note": "refused"}
    else:
        text = "".join(b.text for b in msg.content if b.type == "text")
        try:
            answer = json.loads(text[text.index("{"):text.rindex("}") + 1])
        except ValueError:
            answer = {"verdict": "no evidence", "syllable": "", "url": "", "snippet": "", "note": "unparsable: " + text[:200]}
    return {"word": row["word"], "cedict": row["cedict"], "proposed": row["proposed"], "model": model,
            "method": "search",
            "answer": answer, "usage": usage, "time": time.strftime("%Y-%m-%dT%H:%M:%S")}


class BaiduBlocked(Exception):
    pass


def baidu_fetch(word):
    """Baidu Hanyu's JSON for word: cached in build/neutral/baidu/, else one
    request followed by a pause. None when the request fails."""
    path = os.path.join(BAIDU_RAW, word + ".json")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    url = BAIDU_API + urllib.parse.urlencode({"wd": word, "from": "poem", "pn": 1})
    req = urllib.request.Request(url, headers={"User-Agent": BAIDU_UA, "Referer": "https://hanyu.baidu.com/"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.loads(r.read().decode("utf-8"))
    except Exception as e:   # noqa: BLE001  recorded as "fetch failed"
        log(f"{word}: baidu fetch failed: {type(e).__name__}: {e}")
        return None
    finally:
        time.sleep(BAIDU_PAUSE)
    if "tri_cap" in data or "svcp_url" in data:
        # Baidu's captcha ({"tri_reason": ..., "svcp_url": seccaptcha...}): it came
        # after about 20 requests 2 s apart on 2026-11-21. Never cached.
        raise BaiduBlocked(word)
    os.makedirs(BAIDU_RAW, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    return data


def haiku_fetch(client, word):
    """Baidu's JSON for word through Haiku's web fetch tool: (data or None, usage).
    Raises BaiduBlocked on the captcha. Cached in build/neutral/baidu/ like baidu_fetch."""
    path = os.path.join(BAIDU_RAW, word + ".json")
    usage = {"input": 0, "output": 0, "searches": 0}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f), usage
    url = BAIDU_API + urllib.parse.urlencode({"wd": word, "from": "poem", "pn": 1})
    raw = None
    for attempt in range(3):   # the model sometimes answers without a usable fetch
        msg = client.messages.create(
            model=HAIKU, max_tokens=2000,
            tools=[{"type": "web_fetch_20250910", "name": "web_fetch", "max_uses": 1}],
            messages=[{"role": "user", "content": f"Fetch this URL once with the web_fetch tool, then reply only OK: {url}"}])
        usage["input"] += msg.usage.input_tokens
        usage["output"] += msg.usage.output_tokens
        for b in msg.content:
            if b.type == "web_fetch_tool_result":
                d = b.model_dump()
                raw = ((d.get("content") or {}).get("content") or {}).get("source", {}).get("data") or raw
                if raw is None:
                    log(f"{word}: web fetch result without a document: {json.dumps(d, ensure_ascii=False)[:200]}")
        if raw is not None:
            break
        log(f"{word}: haiku fetch gave no document ({msg.stop_reason}), attempt {attempt + 1}")
    if raw is None:
        return None, usage
    try:
        data = json.loads(raw)
    except ValueError:
        log(f"{word}: haiku fetch not JSON: {raw[:120]!r}")
        return None, usage
    if "tri_cap" in data or "svcp_url" in data:
        raise BaiduBlocked(word)
    os.makedirs(BAIDU_RAW, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    return data, usage


def run_haiku(rows, cache, limit, workers):
    if not os.environ.get("ANTHROPIC_API_KEY"):
        sys.exit("ANTHROPIC_API_KEY is not set for this process")
    import anthropic
    client = anthropic.Anthropic(max_retries=4)
    todo = [r for r in rows if r["wikt_reading"] == "main" and "A" not in r["sources"].split(",")
            and r["word"] not in cache]
    if limit:
        todo = todo[:limit]
    log(f"haiku start: {len(todo)} words")
    counts, spent, blocked = {}, [0.0], threading.Event()

    def one(row):
        if blocked.is_set():
            return
        try:
            data, usage = haiku_fetch(client, row["word"])
        except BaiduBlocked:
            log(f"{row['word']}: captcha through the web fetch tool; stopping")
            blocked.set()
            return
        except Exception as e:   # noqa: BLE001  logged, retried next run
            log(f"{row['word']}: error {type(e).__name__}: {e}")
            return
        ans = baidu_verdict(row, data)
        with lock:
            spent[0] += usage["input"] * HAIKU_PRICE_IN + usage["output"] * HAIKU_PRICE_OUT
            if ans["verdict"] == "fetch failed":
                counts["fetch failed"] = counts.get("fetch failed", 0) + 1
                return
            res = {"word": row["word"], "cedict": row["cedict"], "proposed": row["proposed"], "method": "haiku",
                   "model": HAIKU, "answer": ans, "usage": usage, "time": time.strftime("%Y-%m-%dT%H:%M:%S")}
            with open(CACHE, "a", encoding="utf-8") as f:
                f.write(json.dumps(res, ensure_ascii=False) + "\n")
            v = check(row, ans)
            counts[v] = counts.get(v, 0) + 1
        log(f"{row['word']}: haiku {ans['verdict']} -> {v} {ans['snippet']!r}")

    with ThreadPoolExecutor(workers) as pool:
        list(pool.map(one, todo))
    log(f"haiku done: {counts}, ${spent[0]:.3f}")
    print(f"haiku: {len(todo)} words, {counts}, ${spent[0]:.3f}" + ("; BLOCKED by captcha" if blocked.is_set() else "") + f"; log {LOG}")


def baidu_syllables(pinyin):
    """'jìn·qù' -> [('jìn', False), ('qù', True)]: (syllable, dot before it)."""
    return [(m.group(2), m.group(1) == "·") for m in re.finditer(r"(·?)\s*([^\s·]+)", pinyin.replace("•", "·"))]


def xiandai_style(definition):
    """A definition worded like 现代汉语词典's (an example after ～, no （名）/（动）
    tag and no ［近］ synonyms, which Baidu's other source adds)."""
    return "～" in definition and not definition.startswith("（") and "［" not in definition


# Read through by hand (#64): a dotted line next to a full-tone line that is a
# separate sense, which the ～ test in xiandai_style() misses (no example given).
SENSE_SPLIT = {
    "隔断": "gé duàn 阻绝；使隔开 (verb) / gé·duàn partition (noun)",
    "小月": "xiǎo yuè short month / xiǎo·yuè 〈口〉miscarriage",
}


# Simon's decisions against a lookup that passed check(): never approved.
REJECTED = {
    "狗狗": "keep CC-CEDICT gǒugōu (Simon, 2026-11-21; the only evidence was a Zhihu note)",
}


def baidu_verdict(row, data):
    """{verdict, syllable, url, snippet, note} from Baidu's JSON (module doc)."""
    word, ks = row["word"], neutral_positions(row)
    syl = " ".join(strip_tone(numbered_to_marked(row["proposed"].split()[k])) for k in ks)
    out = {"verdict": "no evidence", "syllable": syl, "url": BAIDU_PAGE + urllib.parse.quote(word),
           "snippet": "", "note": ""}
    if data is None:
        return dict(out, verdict="fetch failed", note="request failed")
    entries = [e for e in (data.get("ret_array") or []) if (e.get("name") or [""])[0] == word]
    if not entries:
        return dict(out, note="word not in Baidu Hanyu")
    letters = [strip_tone(numbered_to_marked(row["proposed"].split()[k])) for k in ks]
    lines, full, toneless, dotted, full_xh = [], [], [], [], []
    for e in entries:
        for m in e.get("mean_list") or []:
            for py in m.get("pinyin") or []:
                lines.append((py, m.get("definition") or []))
        for py in e.get("pinyin") or []:
            lines.append((py, []))
    for py, defs in lines:
        syls = baidu_syllables(py)
        if len(syls) != len(word) or any(strip_tone(syls[k][0].lower()) != letters[i] for i, k in enumerate(ks)):
            continue   # erhua, a different syllable count or another reading
        if all(syls[k][1] for k in ks):
            dotted.append((py, defs))
        elif all(is_toneless(syls[k][0]) for k in ks):
            toneless.append(py)
        else:
            full.append(py)
            full_xh += [(py, d) for d in defs if xiandai_style(d)]
    if dotted:
        py, defs = dotted[0]
        if word in SENSE_SPLIT:
            return dict(out, verdict="both readings", snippet=SENSE_SPLIT[word],
                        note="separate full-tone sense (read by hand): not approved")
        if full_xh:   # 大大: dà dà 表示数量大…：费用～超过了预算 next to dà·da 〈口〉伯父
            fpy, fd = full_xh[0]
            return dict(out, verdict="both readings", snippet=f"{py} / {fpy} {fd[:40]}",
                        note="现汉 also has a full-tone sense: not approved")
        return dict(out, verdict="neutral", snippet=py,
                    note="现代汉语词典 dot: " + (defs[0][:60] if defs else ""))
    for py, defs in lines:
        for d in defs:
            if "轻声" in d:
                return dict(out, verdict="neutral", snippet=d[:120], note=f"轻声 note under {py}")
    if toneless:
        return dict(out, snippet=" / ".join(dict.fromkeys(toneless + full)),
                    note="toneless without the 现汉 dot only")
    if full:
        return dict(out, verdict="not neutral", snippet=" / ".join(dict.fromkeys(full)), note="full tone, no dot")
    return dict(out, snippet=" / ".join(dict.fromkeys(py for py, _ in lines))[:120],
                note="no line with this reading's syllables")


def run_baidu(rows, cache, limit):
    todo = [r for r in rows if r["wikt_reading"] == "main" and "A" not in r["sources"].split(",")
            and r["word"] not in cache]
    if limit:
        todo = todo[:limit]
    log(f"baidu start: {len(todo)} words")
    counts = {}
    for row in todo:
        try:
            data = baidu_fetch(row["word"])
        except BaiduBlocked:
            log(f"{row['word']}: Baidu answered with its captcha; stopping")
            counts["blocked at"] = row["word"]
            break
        ans = baidu_verdict(row, data)
        if ans["verdict"] == "fetch failed":   # not cached: retried next run (or the Haiku fallback)
            counts["fetch failed"] = counts.get("fetch failed", 0) + 1
            continue
        res = {"word": row["word"], "cedict": row["cedict"], "proposed": row["proposed"], "method": "baidu",
               "model": None, "answer": ans, "usage": {"input": 0, "output": 0, "searches": 0},
               "time": time.strftime("%Y-%m-%dT%H:%M:%S")}
        with open(CACHE, "a", encoding="utf-8") as f:
            f.write(json.dumps(res, ensure_ascii=False) + "\n")
        v = check(row, ans)
        counts[v] = counts.get(v, 0) + 1
        log(f"{row['word']}: baidu {ans['verdict']} -> {v} {ans['snippet']!r}")
    log(f"baidu done: {counts}")
    print(f"baidu: {len(todo)} words, {counts}; log {LOG}")


def cost(usage, model=MODEL):
    if model == HAIKU:
        return usage["input"] * HAIKU_PRICE_IN + usage["output"] * HAIKU_PRICE_OUT + usage["searches"] * PRICE_SEARCH
    return usage["input"] * PRICE_IN + usage["output"] * PRICE_OUT + usage["searches"] * PRICE_SEARCH


def write_outputs(rows, cache):
    """Evidence TSV for every candidate, and approved words into the override file."""
    approved, counts = [], {"list": 0, "lookup": 0, "no evidence": 0, "not neutral": 0, "both readings": 0, "not looked up": 0}
    with open(EVIDENCE, "w", encoding="utf-8") as f:
        f.write("word\tverdict\tsyllable\turl\tsnippet\tsource_a\n")
        for row in rows:
            a = "A" in row["sources"].split(",")
            if a:
                verdict, syl, url, snippet = "neutral (must-read list)", "", "", ""
                counts["list"] += 1
            elif row["word"] in cache:
                ans = cache[row["word"]]["answer"]
                raw = os.path.join(BAIDU_RAW, row["word"] + ".json")
                if cache[row["word"]].get("method") in ("baidu", "haiku") and os.path.exists(raw):
                    with open(raw, encoding="utf-8") as rf:   # re-judged with the current rules
                        ans = baidu_verdict(row, json.load(rf))
                verdict = check(row, ans)
                if row["word"] in REJECTED:
                    verdict = "rejected: " + REJECTED[row["word"]]
                syl, url, snippet = ans.get("syllable", ""), ans.get("url", ""), ans.get("snippet", "")
                counts["lookup" if verdict == "neutral" else verdict if verdict in counts else "no evidence"] += 1
            else:
                verdict, syl, url, snippet = "not looked up", "", "", ""
                counts["not looked up"] += 1
            clean = lambda s: re.sub(r"[\t\n\r]+", " ", s)
            f.write("\t".join([row["word"], verdict, clean(syl), clean(url), clean(snippet), "y" if a else "n"]) + "\n")
            if verdict.startswith("neutral"):
                approved.append((row, "must-read list (普通话水平测试)" if a else url))
    with open(OVERRIDES, encoding="utf-8") as f:
        text = f.read()
    marker = "# --- Approved by tools/verify_neutral_tones.py (#60): source, then evidence ---\n"
    text = text.split(marker)[0].rstrip("\n") + "\n"
    hand = {line.split("\t")[0] for line in text.splitlines() if line and not line.startswith("#")}
    text += "\n" + marker
    for row, why in sorted(approved, key=lambda x: x[0]["word"]):
        if row["word"] not in hand:   # hand-written lines above win
            text += f"{row['word']}\t{row['proposed']}\t{why}\n"
    with open(OVERRIDES, "w", encoding="utf-8") as f:
        f.write(text)
    return counts, approved


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--estimate", action="store_true", help="counts and estimated cost only")
    ap.add_argument("--limit", type=int, help="look up at most this many words")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--ruby-only", action="store_true",
                    help="only candidates whose neutral syllable gets pinyin at the default level "
                         "(the scope Simon chose for the first run)")
    ap.add_argument("--write", action="store_true", help="write the evidence TSV and override file only")
    ap.add_argument("--baidu", action="store_true",
                    help="look up the main-reading candidates in Baidu Hanyu (#64): no model, no API key")
    ap.add_argument("--haiku", action="store_true",
                    help="as --baidu, but fetched through Claude Haiku's web fetch tool (#64)")
    ap.add_argument("--haiku-search", action="store_true",
                    help="Haiku 5.5 + web search (any mainland source) for main-reading candidates "
                         "Baidu could not answer (#64)")
    args = ap.parse_args()

    rows = read_candidates()
    cache = read_cache()
    if args.ruby_only:
        rows = [r for r in rows if r["affects_ruby"] == "y"]
    todo = [r for r in rows if "A" not in r["sources"].split(",") and r["word"] not in cache]
    measured = [c["usage"] for c in cache.values()]
    per = (sum(cost(u) for u in measured) / len(measured)) if measured else \
        cost({"input": GUESS_IN, "output": GUESS_OUT, "searches": GUESS_SEARCHES})
    print(f"{len(rows)} candidates: {sum('A' in r['sources'] for r in rows)} from the must-read list (no lookup), "
          f"{len(cache)} looked up already, {len(todo)} to look up; "
          f"${per:.3f} per lookup ({'measured over ' + str(len(measured)) if measured else 'guessed'}), "
          f"estimate ${per * len(todo):.2f}")
    if args.haiku:
        run_haiku(rows, cache, args.limit, args.workers)
        return
    if args.baidu:
        run_baidu(rows, cache, args.limit)
        return
    if args.write:
        counts, _ = write_outputs(rows, cache)
        print(counts)
        return
    if args.estimate:
        return
    if not os.environ.get("ANTHROPIC_API_KEY"):
        sys.exit("ANTHROPIC_API_KEY is not set for this process")
    import anthropic
    client = anthropic.Anthropic(max_retries=4)
    model = MODEL
    if args.haiku_search:
        model = HAIKU
        todo = [r for r in todo if r["wikt_reading"] == "main"]
    if args.limit:
        todo = todo[:args.limit]
    spent = [0.0]

    def one(row):
        try:
            res = lookup(client, row, model)
        except Exception as e:   # noqa: BLE001  logged, retried on the next run
            log(f"{row['word']}: error {type(e).__name__}: {e}")
            return
        with lock:
            with open(CACHE, "a", encoding="utf-8") as f:
                f.write(json.dumps(res, ensure_ascii=False) + "\n")
            spent[0] += cost(res["usage"], model)
        log(f"{row['word']}: {res['answer'].get('verdict')} -> {check(row, res['answer'])} "
            f"(${cost(res['usage'], model):.3f}, total ${spent[0]:.2f})")

    log(f"start: {len(todo)} lookups")
    with ThreadPoolExecutor(args.workers) as pool:
        list(pool.map(one, todo))
    log(f"done: ${spent[0]:.2f}")
    print(f"looked up {len(todo)}, ${spent[0]:.2f}; log {LOG}")


if __name__ == "__main__":
    main()
