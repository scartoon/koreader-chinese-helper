#!/usr/bin/env python3
"""Build the Classical dictionary (#55): the classical senses of single
characters from Chinese Notes, English Wiktionary and (for rare characters)
Unihan, condensed by Claude Haiku into at most five English senses each.
Writes data/classical.tsv.gz, which is committed, so tools/build_db.py needs
no API key: only this script calls the API.

    .venv/bin/python tools/build_classical.py --estimate      # collate, print the cost, call nothing
    ANTHROPIC_API_KEY=... .venv/bin/python tools/build_classical.py --run
    .venv/bin/python tools/build_classical.py                 # write from the cache only
    .venv/bin/python tools/build_classical.py --into chinesehelper.koplugin/data/chinesehelper.sqlite
                                     # (re)write only the classical tables into an existing database

Steps:
  1. Collate (tools/collate_classical.py's extractors), with #49's fixes:
     no CC-CEDICT senses (its own block sits right above), Unihan only for
     characters ranked above 3,000, no Korean/Japanese/Vietnamese Wiktionary
     senses, no Chinese Notes rows without a gloss. MOE stays out (BY-ND).
  2. Condense with tools/condense_classical_prompt.txt (the v3 prompt) and
     claude-haiku-5-5 through the Message Batches API (half price). Every
     reply is cached in build/classical/condense_cache/ under a hash of the
     model, prompt and input (tools/condense_classical.py's key), so a rerun
     only sends new or changed inputs. --run stops before sending if the
     estimate is over --max-usd.
  3. Validate each entry mechanically: senses citing no existing line are
     dropped, entries are cut to five senses, and senses sharing few words
     with their cited lines are flagged (build/classical/flags.tsv) for
     review.
  4. Variant characters with no entry of their own (説 → 說, 衞 → 衛) map to
     one that has an entry, through Unihan's kZVariant and kSemanticVariant.

Output, data/classical.tsv.gz: one row per character, keyed by its
traditional form (a simplified character can stand for several: 发 →
發/髮):
    kind=entry    trad, simp, senses (JSON [{gloss, reading, sources}]), raw (the collated lines)
    kind=variant  the variant, its target (an entry's trad)

Licences: Chinese Notes CC BY-SA 3.0 (adapted under 4.0), Wiktionary CC
BY-SA 4.0, Unihan Unicode License v3; the condensed result is CC BY-SA 4.0.
"""
import argparse
import collections
import csv
import gzip
import hashlib
import io
import json
import os
import re
import sqlite3
import sys
import time
import unicodedata
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import collate_classical as collate  # noqa: E402
import condense_classical as condense  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "build", "classical")
DATA = os.path.join(ROOT, "data", "classical.tsv.gz")
# #67: senses a second check (tools/classical_purity.py, Claude Sonnet) found
# modern-only: headword<TAB>gloss. They are left out of the entries.
MODERN = os.path.join(ROOT, "data", "classical_modern.tsv")
VARIANT = "bundled"
# #67: no cap (every classical sense); this only guards against a runaway reply.
MAX_SENSES = 60
# The input lists the classical sources first and CC-CEDICT last, so the
# order of the lines doesn't push its modern senses to the top.
condense.ORDER = ["wikt", "cn", "unihan", "cedict"]
BATCH_FILE = os.path.join(OUT, "batches.json")
csv.field_size_limit(10 ** 8)


# CC-CEDICT senses that are not senses of the character in a text: names,
# pronunciation notes, classifiers, pointers and colloquial or dialect use.
CEDICT_SKIP = re.compile(r"^(surname |Taiwan pr\.|also pr\.|CL:|used in |see |\((dialect|Tw|slang|coll\.|Cantonese|Internet slang)\))")


def cedict_rows(trads, words=False):
    """Every CC-CEDICT sense of these headwords (#65: characters; #67:
    words of two or more characters with words=True), as collated rows.
    Labelled senses keep their label in the text ("(literary) to
    command"); tag is the label or "candidate"."""
    out = []
    where = "length(simp) > 1" if words else "length(simp) = 1"
    for simp, trad, pinyin, defs in sqlite3.connect(collate.DB).execute(
            f"SELECT simp, trad, pinyin, defs FROM entries WHERE {where} ORDER BY rowid"):
        if trads is not None and trad not in trads:
            continue
        for sense in defs.split("/"):
            sense = sense.strip()
            if not sense or CEDICT_SKIP.match(sense):
                continue
            m = collate.CEDICT_TAG.search(sense)
            out.append(dict(trad=trad, simp=simp, source="cedict", reading=pinyin, sense=sense,
                            tag=(m.group(1) or m.group(2)) if m else "candidate"))
    return out


def cached_rows(path, extract):
    if not os.path.exists(path):
        os.makedirs(OUT, exist_ok=True)
        with open(path, "w", newline="") as f:
            w = csv.DictWriter(f, collate.FIELDS, delimiter="\t")
            w.writeheader()
            w.writerows(extract())
    by = collections.defaultdict(list)
    for r in csv.DictReader(open(path), delimiter="\t"):
        if r["sense"].strip():
            by[r["trad"]].append(r)
    return by


def collated_rows():
    """{trad: [row]} from the bundled sources, for characters and (#67)
    words. Wiktionary, Chinese Notes and rare-character Unihan are cached in
    build/classical/collated-bundled.tsv (characters) and
    collated-words.tsv (words). CC-CEDICT's senses are added for every
    headword that has a classical sense from one of those or a labelled
    classical CC-CEDICT sense, so a headword with only modern CC-CEDICT
    senses gets no entry."""
    def chars():
        rank = dict(sqlite3.connect(collate.DB).execute("SELECT ch, rank FROM chars"))
        return collate.extract_wikt() + collate.extract_cn() + \
            [r for r in collate.extract_unihan(rank) if r["tag"] == "rare"]
    by = cached_rows(os.path.join(OUT, "collated-bundled.tsv"), chars)
    trads = set(by) | {r["trad"] for r in collate.extract_cedict()}
    for r in cedict_rows(trads):
        by[r["trad"]].append(r)
    wby = cached_rows(os.path.join(OUT, "collated-words.tsv"), collate.extract_words)
    allw = cedict_rows(None, words=True)
    wtrads = set(wby) | {r["trad"] for r in allw if r["tag"] != "candidate"}
    for r in allw:
        if r["trad"] in wtrads:
            wby[r["trad"]].append(r)
    by.update(wby)
    return by


def jobs_for(by, prompt, chars=None):
    jobs = []
    for ch in sorted(chars if chars is not None else by):
        if ch not in by:
            continue
        text = condense.input_text(ch, by[ch], VARIANT)
        if text:
            text = text.replace("Character: ", "Headword: ", 1)
            key = hashlib.sha256(json.dumps([condense.MODEL, prompt, VARIANT, text]).encode()).hexdigest()[:24]
            jobs.append((ch, text, key))
    return jobs


def senses_from(reply, text):
    """The reply's senses, or None. A reply that corrects itself ("Wait,
    ... The correct reply is: {...}") counts by its last JSON line."""
    tries = [reply] + [ln for ln in reversed(reply.split("\n")) if ln.startswith('{"senses"')]
    # One brace off at the end (就, 方 in #65): '..."lines": [9]}}]}' or '..."lines": [20]}}'.
    tries += [re.sub(r"\}\}\]\}\s*$", "}]}", reply), re.sub(r"\}\}\s*$", "}]}", reply)]
    for t in tries:
        try:
            return condense.add_sources(json.loads(t)["senses"], text)
        except (ValueError, KeyError, TypeError):
            pass
    return None


def parse_reply(ch, text, msg_content, stop_reason, usage):
    reply = "".join(b.text for b in msg_content if b.type == "text").strip()
    if reply.startswith("```"):
        reply = reply.strip("`").removeprefix("json").strip()
    senses = senses_from(reply, text)
    return {"char": ch, "variant": VARIANT, "model": condense.MODEL, "input": text, "senses": senses,
            "raw_reply": reply if senses is None else None, "stop_reason": stop_reason,
            "usage": {"input": usage.input_tokens, "output": usage.output_tokens}}


def SYSTEM(prompt):
    """The system prompt, cached (#67): about 1,200 tokens sent with every
    request; a cache read costs a tenth."""
    return [{"type": "text", "text": prompt, "cache_control": {"type": "ephemeral"}}]


def estimate_usd(prompt, texts):
    """Batch price: the prompt read from the cache (a tenth), the input and
    about 200 output tokens per request."""
    p = condense.estimate_tokens(prompt)
    tin = sum(p * 0.1 + condense.estimate_tokens(t) for t in texts)
    return (tin / 1e6 * condense.PRICE_IN + 200 * len(texts) / 1e6 * condense.PRICE_OUT) / 2


def run_batches(jobs, prompt, max_usd):
    import anthropic
    from anthropic.types.message_create_params import MessageCreateParamsNonStreaming
    from anthropic.types.messages.batch_create_params import Request
    todo = [j for j in jobs if not os.path.exists(condense.cache_path(j[2]))]
    by_key = {k: (ch, text) for ch, text, k in jobs}
    client = anthropic.Anthropic()          # the key comes from ANTHROPIC_API_KEY only
    state = json.load(open(BATCH_FILE)) if os.path.exists(BATCH_FILE) else []
    pending = [b for b in state if not b.get("collected")]
    if not pending and todo:
        usd = estimate_usd(prompt, [t for _, t, _ in todo])
        print(f"sending {len(todo)} requests, Batch API estimate ~${usd:.2f}")
        if usd > max_usd:
            sys.exit(f"estimate ${usd:.2f} is over --max-usd {max_usd}: not sent")
        for i in range(0, len(todo), 50000):
            chunk = todo[i:i + 50000]
            batch = client.messages.batches.create(requests=[
                Request(custom_id=key, params=MessageCreateParamsNonStreaming(
                    model=condense.MODEL, max_tokens=6000, system=SYSTEM(prompt),
                    thinking={"type": "disabled"},
                    messages=[{"role": "user", "content": text}]))
                for _, text, key in chunk])
            state.append({"id": batch.id, "n": len(chunk), "collected": False})
            json.dump(state, open(BATCH_FILE, "w"))
            print("batch", batch.id, len(chunk))
        pending = [b for b in state if not b.get("collected")]
    used_in = used_out = cache_reads = 0
    for b in pending:
        while True:
            batch = client.messages.batches.retrieve(b["id"])
            if batch.processing_status == "ended":
                break
            c = batch.request_counts
            print(f"{b['id']}: {batch.processing_status}, {c.succeeded} done, {c.processing} processing", flush=True)
            time.sleep(60)
        errors = collections.Counter()
        for res in client.messages.batches.results(b["id"]):
            if res.result.type != "succeeded":
                errors[res.result.type] += 1
                continue
            ch, text = by_key[res.custom_id]
            msg = res.result.message
            rec = parse_reply(ch, text, msg.content, msg.stop_reason, msg.usage)
            json.dump(rec, open(condense.cache_path(res.custom_id), "w"), ensure_ascii=False)
            u = msg.usage
            # Input as billed: cache writes 1.25x, cache reads 0.1x.
            used_in += u.input_tokens + 1.25 * (u.cache_creation_input_tokens or 0) + \
                0.1 * (u.cache_read_input_tokens or 0)
            used_out += u.output_tokens
            cache_reads += u.cache_read_input_tokens or 0
        b["collected"] = True
        b["errors"] = dict(errors)
        json.dump(state, open(BATCH_FILE, "w"))
        print(f"{b['id']}: collected; not succeeded: {dict(errors) or 'none'}")
    if used_in:
        print(f"this run: {used_in:,.0f} billed input (cache reads {cache_reads:,}) + {used_out:,} output tokens, "
              f"${(used_in / 1e6 * condense.PRICE_IN + used_out / 1e6 * condense.PRICE_OUT) / 2:.2f} (batch price)")


def run_sync(jobs, prompt):
    """Prototype runs: send the uncached inputs one by one (standard price)."""
    import anthropic
    client = anthropic.Anthropic()          # the key comes from ANTHROPIC_API_KEY only
    os.makedirs(os.path.join(OUT, "condense_cache"), exist_ok=True)
    used_in = used_out = 0
    for ch, text, key in jobs:
        if os.path.exists(condense.cache_path(key)):
            continue
        msg = client.messages.create(model=condense.MODEL, max_tokens=6000, system=SYSTEM(prompt),
                                     thinking={"type": "disabled"},
                                     messages=[{"role": "user", "content": text}])
        rec = parse_reply(ch, text, msg.content, msg.stop_reason, msg.usage)
        json.dump(rec, open(condense.cache_path(key), "w"), ensure_ascii=False)
        used_in += msg.usage.input_tokens
        used_out += msg.usage.output_tokens
    print(f"this run: {used_in:,} input + {used_out:,} output tokens, "
          f"${used_in / 1e6 * condense.PRICE_IN + used_out / 1e6 * condense.PRICE_OUT:.3f}")


WORD = re.compile(r"[a-z]+")
STOP = set("a an the of to in on or and as for by with from at be is it its one sth sb someone something "
           "used also eg ie etc kind type form".split())


def content_words(s):
    return {w for w in WORD.findall(s.lower()) if w not in STOP and len(w) > 2}


def toneless(s):
    return "".join(c for c in unicodedata.normalize("NFD", s) if not unicodedata.combining(c)).lower()


def reading_only(line):
    """True for a collated line that gives a reading and no sense: Chinese
    Notes rows whose English is just the toneless pinyin ("[CN] lǎn lan"),
    or that and "radical" ("[CN] fù fu radical")."""
    words = re.sub(r"^\[\w+\]\s*", "", line).split()
    if not words:
        return True
    reading = toneless(words[0])
    rest = [toneless(w).strip("();,.") for w in words[1:]]
    return reading in rest and all(w in (reading, "", "radical") for w in rest)


# Glosses that only report the input had no sense (囕 "lan (reading only;
# no sense given)"); "particle with no meaning" is a real sense and stays.
NO_SENSE = re.compile(r"no (classical |further )?(sense|gloss)|no meaning (given|supplied)|reading only"
                      r"|only a reading|sense unspecified|kwukyel", re.I)


def validate(rec):
    """(senses kept, flags): drop senses citing no existing line and (#67)
    senses the reply marks modern-only ("classical": false), flag English
    senses sharing under half their words with the cited lines."""
    lines = {}
    for line in rec["input"].split("\n")[1:]:
        num, rest = line.split(". ", 1)
        lines[int(num)] = rest
    kept, flags = [], []
    for s in rec["senses"] or []:
        cited = [n for n in s.get("lines", []) if isinstance(n, int) and n in lines]
        gloss = (s.get("gloss") or "").strip()
        if not cited or not gloss:
            flags.append(("no-line", gloss))
            continue
        if NO_SENSE.search(gloss) or all(reading_only(lines[n]) for n in cited):
            flags.append(("no-sense", gloss + "  <=  " + " | ".join(lines[n] for n in cited)))
            continue
        if s.get("classical") is False:
            flags.append(("modern", gloss + "  <=  " + " | ".join(lines[n] for n in cited)))
            continue
        words = content_words(gloss)
        src = set().union(*(content_words(lines[n]) for n in cited))
        stems = {w[:5] for w in src}
        missing = [w for w in words if w not in src and w[:5] not in stems]
        if words and len(missing) * 2 > len(words):
            flags.append(("few-words", gloss + "  <=  " + " | ".join(lines[n] for n in cited)))
        kept.append({"gloss": gloss, "reading": s.get("reading") or "", "sources": s["sources"]})
    # The popup shows "reading: gloss" only to tell readings apart (#53):
    # an entry whose senses all share one reading shows none (v4 replies
    # often give the reading on every sense).
    if len({s["reading"] for s in kept if s["reading"]}) <= 1:
        for s in kept:
            s["reading"] = ""
    if len(kept) > MAX_SENSES:
        flags.append(("over-cap", str(len(kept))))
        kept = kept[:MAX_SENSES]
    return kept, flags


def variants(entries):
    """{variant: target} for characters with no entry whose Unihan kZVariant
    or kSemanticVariant has one (the target with the most senses wins)."""
    z = zipfile.ZipFile(os.path.join(collate.SRC, "unihan", "Unihan.zip"))
    cands = collections.defaultdict(set)
    for line in io.TextIOWrapper(z.open("Unihan_Variants.txt"), encoding="utf-8"):
        if line.startswith("#") or not line.strip():
            continue
        cp, field, value = line.rstrip("\n").split("\t")
        if field not in ("kZVariant", "kSemanticVariant"):
            continue
        ch = chr(int(cp[2:], 16))
        for v in value.split():
            cands[ch].add(chr(int(v.split("<")[0][2:], 16)))
    out = {}
    for ch, targets in cands.items():
        if ch in entries:
            continue
        have = [t for t in targets if t in entries]
        if have:
            out[ch] = max(have, key=lambda t: (len(entries[t]["senses"]), t))
    return out


# Keep in step with DB.classicalSql and DB.classicalVariantSql in chinesehelper.koplugin/ch_db.lua.
CLASSICAL_SQL = "SELECT trad, simp, senses FROM classical WHERE trad = ? OR simp = ? ORDER BY trad"
VARIANT_SQL = "SELECT trad FROM classical_variant WHERE ch = ?"
# DB.classicalWordsSql(2) (#67).
CLASSICAL_WORDS_SQL = "SELECT trad, simp, senses FROM classical WHERE trad IN (?,?) OR simp IN (?,?) ORDER BY trad"
SCHEMA = """
CREATE TABLE classical (trad TEXT PRIMARY KEY, simp TEXT NOT NULL, senses TEXT NOT NULL, raw TEXT NOT NULL) WITHOUT ROWID;
-- senses: one "reading<TAB>gloss<TAB>sources" line per sense; raw: the collated input lines
CREATE INDEX classical_simp ON classical(simp);
CREATE TABLE classical_variant (ch TEXT PRIMARY KEY, trad TEXT NOT NULL) WITHOUT ROWID;
"""


def read_data(path=DATA):
    entries, var = [], []
    with gzip.open(path, "rt", encoding="utf-8", newline="") as f:
        for row in csv.reader((line for line in f if not line.startswith("#")), delimiter="\t"):
            if row[0] == "entry":
                # For the plugin: one "reading<TAB>gloss<TAB>sources" line per
                # sense (no JSON decoder needed on the device).
                senses = "\n".join("\t".join((s["reading"], s["gloss"], ",".join(s["sources"])))
                                   for s in json.loads(row[3]))
                entries.append((row[1], row[2], senses, row[4]))
            elif row[0] == "variant":
                var.append((row[1], row[2]))
    return entries, var


def write_tables(con, path=DATA):
    """The classical tables from data/classical.tsv.gz into an open database
    (replacing any there). Returns the meta rows."""
    entries, var = read_data(path)
    con.executescript("DROP TABLE IF EXISTS classical; DROP TABLE IF EXISTS classical_variant;" + SCHEMA)
    con.executemany("INSERT INTO classical VALUES (?, ?, ?, ?)", entries)
    con.executemany("INSERT INTO classical_variant VALUES (?, ?)", var)
    with open(path, "rb") as f:
        sha = hashlib.sha256(f.read()).hexdigest()
    return {"classical": str(len(entries)), "classical_variants": str(len(var)), "classical_sha256": sha,
            "classical_model": condense.MODEL,
            "classical_license": "CC BY-SA 4.0 (condensed by Claude Haiku from Chinese Notes CC BY-SA 3.0, "
                                 "English Wiktionary CC BY-SA 4.0, Unihan Unicode License v3)"}


def check_plans(con):
    for sql, n, want in ((CLASSICAL_SQL, 2, ("USING PRIMARY KEY", "USING INDEX classical_simp")),
                         (CLASSICAL_WORDS_SQL, 4, ("USING PRIMARY KEY", "USING INDEX classical_simp")),
                         (VARIANT_SQL, 1, ("USING PRIMARY KEY",))):
        plan = "\n".join(r[3] for r in con.execute("EXPLAIN QUERY PLAN " + sql, ["x"] * n))
        if any(w not in plan for w in want) or re.search(r"\bSCAN classical", plan):
            sys.exit(f"Query does not use its index:\n{sql}\n{plan}")
        print("Query plan ok: " + sql[:60] + "\n    " + plan.replace("\n", "\n    "))


def into(db):
    con = sqlite3.connect(db)
    meta = write_tables(con)
    con.executemany("INSERT OR REPLACE INTO meta VALUES (?, ?)", meta.items())
    con.commit()
    con.execute("VACUUM")
    check_plans(con)
    con.close()
    print(f"{db}: {meta['classical']} classical entries, {meta['classical_variants']} variants, "
          f"{os.path.getsize(db) / 1e6:.1f} MB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--into", metavar="DB", help="only write the classical tables into this database")
    ap.add_argument("--estimate", action="store_true", help="collate and print the cost; call nothing")
    ap.add_argument("--run", action="store_true", help="send the uncached inputs through the Batch API")
    ap.add_argument("--max-usd", type=float, default=5.0)
    ap.add_argument("--chars-file", help="prototype: only these characters, sent one by one (not batched)")
    ap.add_argument("--out", default=DATA, help="where to write the data file (default data/classical.tsv.gz)")
    args = ap.parse_args()
    if args.into:
        return into(args.into)
    prompt = open(condense.PROMPT).read()
    by = collated_rows()
    chars = None
    if args.chars_file:
        # Whitespace-separated: a token that is a word headword stays whole,
        # any other token is split into its characters.
        toks = open(args.chars_file).read().split()
        chars = list(dict.fromkeys(x for t in toks for x in ([t] if len(t) > 1 and t in by else list(t))))
    jobs = jobs_for(by, prompt, chars)
    cached = sum(os.path.exists(condense.cache_path(k)) for *_, k in jobs)
    est_in = sum(condense.estimate_tokens(prompt) + condense.estimate_tokens(t) for _, t, _ in jobs)
    usd = estimate_usd(prompt, [t for _, t, k in jobs if not os.path.exists(condense.cache_path(k))])
    print(f"{len(jobs)} characters ({cached} cached); all inputs ~{est_in:,.0f} tokens; "
          f"to send: ~${usd:.2f} at batch price")
    if args.estimate:
        return
    if args.run and chars is not None:
        run_sync(jobs, prompt)
    elif args.run:
        run_batches(jobs, prompt, args.max_usd)
    modern = set()
    if os.path.exists(MODERN):
        for line in open(MODERN):
            if not line.startswith("#") and "\t" in line:
                modern.add(tuple(line.rstrip("\n").split("\t")[:2]))
    entries, flags, missing, unparsed = {}, [], 0, []
    for ch, text, key in jobs:
        path = condense.cache_path(key)
        if not os.path.exists(path):
            missing += 1
            continue
        rec = json.load(open(path))
        if rec["senses"] is None and rec.get("raw_reply"):
            rec["senses"] = senses_from(rec["raw_reply"], text)
        if rec["senses"] is None:
            unparsed.append(ch)
            continue
        senses, fl = validate(rec)
        flags += [(ch, kind, detail) for kind, detail in fl]
        flags += [(ch, "modern-check", s["gloss"]) for s in senses if (ch, s["gloss"]) in modern]
        senses = [s for s in senses if (ch, s["gloss"]) not in modern]
        if senses:
            entries[ch] = {"simp": by[ch][0]["simp"], "senses": senses,
                           "raw": "\n".join(text.split("\n")[1:])}
    # A simplified character with an entry of its own drawn only from
    # Unihan (讬, 砻) is also the simp of a traditional entry (託, 礱). The
    # popup prefers the tapped character's own entry, so this thin copy
    # would hide the traditional one: drop it, and the simp lookup finds 託.
    simps = {e["simp"] for t, e in entries.items() if e["simp"] != t}
    # #67: CC-CEDICT's "variant of 託" counts as thin too (讬).
    thin = [t for t, e in entries.items() if t in simps and e["simp"] == t
            and all(s["sources"] == ["Unihan"] or s["gloss"].startswith("variant of") for s in e["senses"])]
    for t in thin:
        del entries[t]
    var = {v: t for v, t in variants(entries).items() if v not in simps}
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with gzip.open(args.out, "wt", encoding="utf-8", newline="", compresslevel=9) as f:
        f.write("# Classical dictionary (tools/build_classical.py, #55, #65). CC BY-SA 4.0: condensed by Claude Haiku\n"
                "# from CC-CEDICT (CC BY-SA 4.0), Chinese Notes (CC BY-SA 3.0), English Wiktionary (CC BY-SA 4.0)\n"
                "# and Unihan (Unicode License v3).\n")
        w = csv.writer(f, delimiter="\t", lineterminator="\n", quoting=csv.QUOTE_MINIMAL)
        for ch in sorted(entries):
            e = entries[ch]
            w.writerow(["entry", ch, e["simp"], json.dumps(e["senses"], ensure_ascii=False), e["raw"]])
        for ch in sorted(var):
            w.writerow(["variant", ch, var[ch], "", ""])
    with open(os.path.join(OUT, "flags.tsv" if chars is None else "flags-proto.tsv"), "w") as f:
        for row in flags:
            f.write("\t".join(row) + "\n")
    kinds = collections.Counter(k for _, k, _ in flags)
    print(f"wrote {args.out}: {len(entries)} entries, {len(var)} variants; "
          f"{len(thin)} Unihan-only simplified copies dropped; {missing} not condensed yet, {len(unparsed)} unparsed {''.join(unparsed[:20])}; flags {dict(kinds)}")


if __name__ == "__main__":
    main()
