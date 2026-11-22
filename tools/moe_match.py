#!/usr/bin/env python3
"""Match the 文言 entries' untagged CC-CEDICT senses to MOE evidence (#69).

A sense of the condensed entries (build/classical/condense_cache/, the v5b
replies) that cites only untagged CC-CEDICT lines is a candidate: it stays
in the 文言 entry only if MOE (重編國語辭典) gives the same sense with a
quotation from a classical-register work up to 1911
(tools/moe_evidence.py decides which quotes count).

Claude Haiku only compares texts: for each English sense, which numbered MOE
definition of the same headword has the same meaning, or none. It sees all
of the headword's MOE definitions (not only those with a qualifying quote,
so a near miss is not forced onto the closest qualifying one); the build
then keeps a sense only if its matched definition has a qualifying quote.
Headwords with no qualifying MOE definition need no request.

    .venv/bin/python tools/moe_match.py --estimate
    ANTHROPIC_API_KEY=... .venv/bin/python tools/moe_match.py --run --chars-file build/classical/proto67.txt   # one by one
    ANTHROPIC_API_KEY=... .venv/bin/python tools/moe_match.py --run                                          # Batch API
    .venv/bin/python tools/moe_match.py            # write build/classical/moe_matches.tsv from the cache

Replies are cached in build/classical/moe_match_cache/ under a hash of the
model, prompt and input. build/classical/moe_matches.tsv (git-ignored: it
quotes MOE) records every candidate's decision and, for kept ones, the MOE
definition and quotation that backed it; tools/build_classical.py reads the
decisions from it.
"""
import argparse
import collections
import csv
import hashlib
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_classical as bc  # noqa: E402
import condense_classical as condense  # noqa: E402
import moe_evidence as moe  # noqa: E402

OUT = bc.OUT
CACHE = os.path.join(OUT, "moe_match_cache")
MATCHES = os.path.join(OUT, "moe_matches.tsv")
BATCH_FILE = os.path.join(OUT, "moe_match_batches.json")
MODEL = condense.MODEL
TAGGED = re.compile(r"\((literary|classical|archaic|old|obsolete)\)")

PROMPT = """You compare two dictionaries of Chinese. For one headword you get its English senses (lettered A, B, C...) and its definitions from a Chinese dictionary (numbered 1, 2, 3...; each may show its reading).

For each English sense, give the number of the Chinese definition that has the same meaning, or 0 if none does.

Rules:
- Same meaning means the English sense translates that definition: the same thing, action, quality or function, not merely a related idea. "to want to" is not "to need to"; "then, at once" is not "near, to approach"; "possessive particle" is not "target, bullseye".
- A definition that covers more than the English sense (a broader definition including it) counts as the same meaning. One whose meaning is only similar, derived or figurative (when the English is literal), or the other way round, does not.
- Several English senses may match the same definition. If two definitions both have the same meaning, give the one that fits best.
- A reading shown with a definition must fit: a sense of a different reading only matches if the meaning is clearly the same.
- When unsure, give 0.

Reply with one JSON object and nothing else, mapping each letter to a number: {"A": 3, "B": 0}"""


def tagged_line(line):
    return not line.startswith("[CEDICT]") or bool(TAGGED.search(line))


def split_senses(rec, text):
    """The reply's senses as (sense, kind): kind is "tagged" when a cited
    line is a dictionary-tagged classical one (kept whatever the reply's
    classical mark says), "candidate" when it cites only untagged CC-CEDICT
    lines, None when it cites no existing line."""
    lines = {}
    for line in text.split("\n")[1:]:
        num, rest = line.split(". ", 1)
        lines[int(num)] = rest
    out = []
    for s in rec["senses"] or []:
        cited = [n for n in s.get("lines", []) if isinstance(n, int) and n in lines]
        if not cited:
            out.append((s, None))
        elif any(tagged_line(lines[n]) for n in cited):
            out.append((s, "tagged"))
        else:
            out.append((s, "candidate"))
    return out


def cached_rec(text, key):
    path = condense.cache_path(key)
    if not os.path.exists(path):
        return None
    rec = json.load(open(path))
    if rec["senses"] is None and rec.get("raw_reply"):
        rec["senses"] = bc.senses_from(rec["raw_reply"], text)
    return rec if rec["senses"] is not None else None


def letters(n):
    return [chr(65 + i) if i < 26 else "A" + chr(65 + i - 26) for i in range(n)]


def match_input(head, glosses, defs):
    out = [f"Headword: {head}", "", "English senses:"]
    out += [f"{L}. {g}" for L, g in zip(letters(len(glosses)), glosses)]
    out += ["", "Chinese definitions:"]
    multi = len({p for p, *_ in defs}) > 1
    for pinyin, n, d, _ in defs:
        out.append(f"{n}. " + (f"({pinyin}) " if multi and pinyin else "") + d)
    return "\n".join(out)


def candidates(chars=None):
    """[(headword, [glosses], [MOE definitions], input, key)] for headwords
    with candidate senses and at least one qualifying MOE definition, plus
    [(headword, [glosses])] for those with no qualifying MOE definition."""
    prompt = open(condense.PROMPT).read()
    by = bc.collated_rows()
    data = moe.load()
    vern = moe.vernacular_titles(data)
    heads = moe.by_headword(data)
    jobs, no_moe = [], []
    for ch, text, key in bc.jobs_for(by, prompt, chars):
        rec = cached_rec(text, key)
        if rec is None:
            continue
        glosses = list(dict.fromkeys((s.get("gloss") or "").strip() for s, kind in split_senses(rec, text)
                                     if kind == "candidate" and (s.get("gloss") or "").strip()))
        if not glosses:
            continue
        defs = moe.all_definitions(heads[ch], vern) if ch in heads else []
        if not any(q for *_, q in defs):
            no_moe.append((ch, glosses))
            continue
        inp = match_input(ch, glosses, defs)
        mkey = hashlib.sha256(json.dumps([MODEL, PROMPT, inp]).encode()).hexdigest()[:24]
        jobs.append((ch, glosses, defs, inp, mkey))
    return jobs, no_moe


def cache_file(key):
    return os.path.join(CACHE, key + ".json")


def parse(reply, n):
    reply = reply.strip()
    if reply.startswith("```"):
        reply = reply.strip("`").removeprefix("json").strip()
    m = re.search(r"\{.*\}", reply, re.S)
    try:
        d = json.loads(m.group(0)) if m else None
    except ValueError:
        return None
    if not isinstance(d, dict):
        return None
    return [d.get(L) if isinstance(d.get(L), int) else 0 for L in letters(n)]


def system():
    return [{"type": "text", "text": PROMPT, "cache_control": {"type": "ephemeral"}}]


def save(key, msg):
    reply = "".join(b.text for b in msg.content if b.type == "text")
    json.dump({"model": MODEL, "reply": reply, "stop_reason": msg.stop_reason,
               "usage": {"input": msg.usage.input_tokens, "output": msg.usage.output_tokens,
                         "cache_read": msg.usage.cache_read_input_tokens or 0,
                         "cache_write": msg.usage.cache_creation_input_tokens or 0}},
              open(cache_file(key), "w"), ensure_ascii=False)


def billed(u):
    return (u["input"] + 1.25 * u["cache_write"] + 0.1 * u["cache_read"]) / 1e6 * condense.PRICE_IN + \
        u["output"] / 1e6 * condense.PRICE_OUT


def estimate_usd(jobs):
    p = condense.estimate_tokens(PROMPT)
    tin = sum(p * 0.1 + condense.estimate_tokens(j[3]) for j in jobs)
    tout = sum(8 * len(j[1]) + 5 for j in jobs)
    return (tin / 1e6 * condense.PRICE_IN + tout / 1e6 * condense.PRICE_OUT) / 2


def run_sync(jobs):
    import anthropic
    client = anthropic.Anthropic()          # the key comes from ANTHROPIC_API_KEY only
    usd = 0.0
    for ch, glosses, defs, inp, key in jobs:
        if os.path.exists(cache_file(key)):
            continue
        msg = client.messages.create(model=MODEL, max_tokens=1000, system=system(),
                                     thinking={"type": "disabled"},
                                     messages=[{"role": "user", "content": inp}])
        save(key, msg)
        usd += billed(json.load(open(cache_file(key)))["usage"])
    print(f"this run: ${usd:.3f} (standard price)")


def run_batches(jobs, max_usd):
    import anthropic
    from anthropic.types.message_create_params import MessageCreateParamsNonStreaming
    from anthropic.types.messages.batch_create_params import Request
    client = anthropic.Anthropic()          # the key comes from ANTHROPIC_API_KEY only
    todo = [j for j in jobs if not os.path.exists(cache_file(j[4]))]
    todo = list({j[4]: j for j in todo}.values())
    state = json.load(open(BATCH_FILE)) if os.path.exists(BATCH_FILE) else []
    pending = [b for b in state if not b.get("collected")]
    if not pending and todo:
        usd = estimate_usd(todo)
        print(f"sending {len(todo)} requests, Batch API estimate ~${usd:.2f}")
        if usd > max_usd:
            sys.exit(f"estimate ${usd:.2f} is over --max-usd {max_usd}: not sent")
        batch = client.messages.batches.create(requests=[
            Request(custom_id=key, params=MessageCreateParamsNonStreaming(
                model=MODEL, max_tokens=1000, system=system(), thinking={"type": "disabled"},
                messages=[{"role": "user", "content": inp}]))
            for _, _, _, inp, key in todo])
        state.append({"id": batch.id, "n": len(todo), "collected": False})
        json.dump(state, open(BATCH_FILE, "w"))
        print("batch", batch.id, len(todo), flush=True)
        pending = [b for b in state if not b.get("collected")]
    usd = 0.0
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
            save(res.custom_id, res.result.message)
            usd += billed(json.load(open(cache_file(res.custom_id)))["usage"]) / 2
        b["collected"] = True
        b["errors"] = dict(errors)
        json.dump(state, open(BATCH_FILE, "w"))
        print(f"{b['id']}: collected; not succeeded: {dict(errors) or 'none'}")
    if usd:
        print(f"this run: ${usd:.2f} (batch price)")


def source_of(quote):
    """The work a quote cites, without the quoted text."""
    return quote.split("：「")[0].split("：")[0]


def write_matches(jobs, no_moe, path=MATCHES):
    """One row per candidate sense: headword, gloss, decision (kept / no-match
    / unqualified / no-moe / unanswered), MOE definition number, definition,
    the quote's source and the quote."""
    counts = collections.Counter()
    with open(path, "w", newline="") as f:
        w = csv.writer(f, delimiter="\t", lineterminator="\n")
        w.writerow(["headword", "gloss", "decision", "moe_def", "definition", "source", "quote"])
        for ch, glosses in no_moe:
            for g in glosses:
                w.writerow([ch, g, "no-moe", "", "", "", ""])
                counts["no-moe"] += 1
        for ch, glosses, defs, inp, key in jobs:
            got = None
            if os.path.exists(cache_file(key)):
                got = parse(json.load(open(cache_file(key)))["reply"], len(glosses))
            byn = {n: (d, q) for _, n, d, q in defs}
            for i, g in enumerate(glosses):
                n = got[i] if got else None
                if got is None:
                    row = [ch, g, "unanswered", "", "", "", ""]
                elif not n or n not in byn:
                    row = [ch, g, "no-match", "", "", "", ""]
                elif byn[n][1] is None:
                    row = [ch, g, "unqualified", n, byn[n][0], "", ""]
                else:
                    row = [ch, g, "kept", n, byn[n][0], source_of(byn[n][1]), byn[n][1]]
                counts[row[2]] += 1
                w.writerow(row)
    return counts


def read_matches(path=MATCHES):
    """{(headword, gloss): decision} from moe_matches.tsv."""
    if not os.path.exists(path):
        return {}
    return {(r["headword"], r["gloss"]): r["decision"] for r in csv.DictReader(open(path), delimiter="\t")}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--estimate", action="store_true")
    ap.add_argument("--run", action="store_true")
    ap.add_argument("--max-usd", type=float, default=5.0)
    ap.add_argument("--chars-file", help="prototype: only these headwords, sent one by one")
    ap.add_argument("--out", default=MATCHES)
    args = ap.parse_args()
    os.makedirs(CACHE, exist_ok=True)
    chars = None
    if args.chars_file:
        by = bc.collated_rows()
        toks = open(args.chars_file).read().split()
        chars = list(dict.fromkeys(x for t in toks for x in ([t] if len(t) > 1 and t in by else list(t))))
    jobs, no_moe = candidates(chars)
    todo = [j for j in jobs if not os.path.exists(cache_file(j[4]))]
    print(f"{len(jobs)} headwords to match ({len(jobs) - len(todo)} cached), "
          f"{sum(len(j[1]) for j in jobs)} candidate senses; {sum(len(g) for _, g in no_moe)} candidates on {len(no_moe)} headwords have no qualifying MOE "
          f"definition (dropped, no request); to send ~${estimate_usd(todo):.2f} at batch price")
    if args.estimate:
        return
    if args.run and chars is not None:
        run_sync(todo)
    elif args.run:
        run_batches(jobs, args.max_usd)
    counts = write_matches(jobs, no_moe, args.out)
    print(f"wrote {args.out}: {dict(counts)}")


if __name__ == "__main__":
    main()
