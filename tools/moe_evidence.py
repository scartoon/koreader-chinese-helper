#!/usr/bin/env python3
"""MOE evidence for the 文言 entries (#69): which MOE (重編國語辭典修訂本)
definitions are quoted from a classical-register work written up to the end
of the Qing (1911).

    .venv/bin/python tools/moe_evidence.py --sample 50     # print a random sample of classified quotes
    .venv/bin/python tools/moe_evidence.py --word 花甲     # one headword's qualifying definitions

A quote qualifies (classical_quote) unless:
  - it was written after 1911: its dynasty is 民國, 近代 or 現代, or it is
    《清史稿》 (compiled 1914-1927);
  - it is undated and not a classic
    (《…》), a commentary (注, 疏, 集解, 索隱…) or a 詩序/章句 note;
  - it is from a vernacular novel or story collection: a work MOE ever cites
    by chapter (第…回), the 三言二拍 and other 話本 collections, or a title
    with 演義/平話/話本/通俗;
  - it is from drama or song: a work MOE ever cites by act or scene (第…折,
    第…齣, 楔子), a 雜劇/元曲 title, or a 散曲 (〈…〉曲).

MOE's text is CC BY-ND 3.0 TW: nothing from here is shipped. The build keeps
only the yes/no decision for each sense, and (for audit, in build/) which
definition and quote backed it.
"""
import argparse
import collections
import json
import lzma
import os
import random
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOE = os.path.join(ROOT, "build", "sources", "moe", "dict-revised.json.xz")

NUM = "[一二三四五六七八九十百〇零\\d]+"
CHAPTER = re.compile(f"第{NUM}回")
ACT = re.compile(f"第{NUM}[折齣出]|楔子")
TITLE = re.compile(r"《([^》．]+)")
MODERN = {"民國", "中華民國", "近代", "現代", "當代"}
# Vernacular story collections MOE cites by 卷 or story title, not by 回.
STORIES = {"醒世恆言", "喻世明言", "警世通言", "古今小說", "初刻拍案驚奇", "二刻拍案驚奇", "拍案驚奇",
           "今古奇觀", "京本通俗小說", "大宋宣和遺事", "清平山堂話本", "石點頭", "型世言", "西湖二集",
           "豆棚閒話", "豆棚閑話", "無聲戲", "照世杯", "十二樓", "醉醒石", "五代史平話", "三國志平話",
           "大唐三藏取經詩話", "宣和遺事", "雨窗欹枕集", "樂府群珠", "元曲選", "全元散曲", "雍熙樂府",
           "太和正音譜", "盛世新聲", "詞林摘豔", "陽春白雪", "太平樂府"}
# Classical-register works written after 1911 (清史稿 was compiled 1914-1927).
AFTER_1911 = {"清史稿"}
VERNACULAR_WORD = re.compile(r"演義|平話|話本|通俗|雜劇|元曲|散曲|諸宮調|傳奇三集")
# Undated quotes that are still classical: commentaries and notes on the classics.
COMMENTARY = re.compile(r"^(\S{0,8}(注|疏|集解|索隱|正義|箋|傳)(引|曰|云|：)|根據〈詩序〉|[首本次卒]章\S{1,3}句為|"
                        r"語[本出]|朱傳|自注|注：|段注本|大徐本|小徐本)")


def clean(q):
    return q.replace("﻿", "").replace("・", "．").strip()


def load():
    return json.load(lzma.open(MOE))


def vernacular_titles(data):
    """Titles MOE ever cites by chapter (novels) or by act (drama)."""
    out = set(STORIES)
    for e in data:
        for h in e.get("heteronyms", []):
            for df in h.get("definitions", []):
                for q in df.get("quote", []):
                    q = clean(q)
                    m = TITLE.search(q)
                    if not m:
                        continue
                    head = q.split("：")[0]
                    if CHAPTER.search(head) or ACT.search(head):
                        out.add(m.group(1))
    return out


def classify(q, vern):
    """(qualifies, reason) for one MOE quote."""
    q = clean(q)
    head = q.split("：")[0].split("「")[0]
    dyn = re.match(r"^([^．《〈「：]{1,6})．", q)
    if dyn and dyn.group(1) in MODERN:
        return False, "modern"
    if CHAPTER.search(head):
        return False, "novel"
    if ACT.search(head):
        return False, "drama"
    if re.search(r"〉\S{0,3}曲|曲》|套．", head):
        return False, "song"
    titles = TITLE.findall(head)
    if any(t in AFTER_1911 for t in titles):
        return False, "after-1911"
    if any(t in vern or VERNACULAR_WORD.search(t) for t in titles):
        return False, "vernacular-title"
    if VERNACULAR_WORD.search(head):
        return False, "vernacular-title"
    if not dyn and not q.startswith(("《", "〈")) and not COMMENTARY.match(q):
        return False, "undated"
    return True, "classical"


def all_definitions(entry, vern):
    """[(pinyin, def number, definition, first qualifying quote or None)]
    for one MOE entry, numbered in order across its heteronyms."""
    out, n = [], 0
    for h in entry.get("heteronyms", []):
        for df in h.get("definitions", []):
            n += 1
            good = [clean(q) for q in df.get("quote", []) if classify(q, vern)[0]]
            out.append((h.get("pinyin", ""), n, df.get("def", "").strip(), good[0] if good else None))
    return out


def by_headword(data):
    """{headword: MOE entry} (the first entry for a repeated title)."""
    out = {}
    for e in data:
        w = clean(e.get("title", ""))
        if w and "{" not in w:
            out.setdefault(w, e)
    return out


def qualifying_definitions(data, vern):
    """{headword: [(heteronym pinyin, def number, definition, quote)]}: every
    MOE definition with at least one qualifying quote, numbered in order
    across the headword's heteronyms (1, 2, ...). The quote is the first
    qualifying one."""
    out = {}
    for e in data:
        w = clean(e.get("title", ""))
        if not w or "{" in w:
            continue
        defs, n = [], 0
        for h in e.get("heteronyms", []):
            for df in h.get("definitions", []):
                n += 1
                good = [clean(q) for q in df.get("quote", []) if classify(q, vern)[0]]
                if good:
                    defs.append((h.get("pinyin", ""), n, df.get("def", "").strip(), good[0]))
        if defs:
            out[w] = defs
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sample", type=int, default=0)
    ap.add_argument("--seed", type=int, default=69)
    ap.add_argument("--word")
    args = ap.parse_args()
    data = load()
    vern = vernacular_titles(data)
    if args.word:
        for row in qualifying_definitions([e for e in data if clean(e.get("title", "")) == args.word], vern).get(args.word, []):
            print(*row, sep="\t")
        return
    qs = [clean(q) for e in data for h in e.get("heteronyms", []) for df in h.get("definitions", [])
          for q in df.get("quote", [])]
    counts = collections.Counter(classify(q, vern)[1] for q in qs)
    print(f"{len(qs)} quotes, {len(vern)} vernacular titles: {dict(counts.most_common())}")
    if args.sample:
        random.seed(args.seed)
        for q in random.sample(qs, args.sample):
            ok, why = classify(q, vern)
            print(f"{'Y' if ok else 'n'}\t{why}\t{q[:100]}")


if __name__ == "__main__":
    main()
