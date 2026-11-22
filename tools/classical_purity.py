#!/usr/bin/env python3
"""#67: a second check on the senses of the Classical dictionary that come
only from CC-CEDICT's unlabelled lines (where modern-only senses slip
through). One request per entry lists those senses; the model answers, for
each, whether it is used in classical texts. Replies cached in
build/classical/purity/<model>/.

    ANTHROPIC_API_KEY=... .venv/bin/python tools/classical_purity.py --model claude-haiku-5-5 --chars-file F
"""
import argparse, concurrent.futures as cf, csv, gzip, hashlib, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "build", "classical", "purity")
DATA = os.path.join(ROOT, "data", "classical.tsv.gz")
csv.field_size_limit(10 ** 8)

PROMPT = """You check a dictionary of classical Chinese (文言): the language of pre-Qin and Han prose, the histories, classical essays and Tang–Song classical prose and poetry. Senses that exist only in vernacular (白话) or modern Chinese must not be in it.

You get several headwords. For each: its full entry for context, and the senses to check, numbered like 3.1 (headword 3, sense 1). For each sense to check, decide:
- "classical": the headword has this sense in classical texts (whether or not modern Chinese also has it).
- "modern": the sense is found only in vernacular or modern Chinese: modern Mandarin grammar (structural particles like 的/地/得 as 'of' or adverb markers, aspect particles, 就/才/都/还 as modern adverbs, sentence patterns), new meanings, things or institutions of later times, colloquial senses, classifiers that are modern usage.
Judge each sense on its own. Reply with JSON only, one verdict per sense to check: {"verdicts": [{"id": "3.1", "v": "classical" | "modern"}]}"""


def entries():
    for r in csv.reader((l for l in gzip.open(DATA, "rt") if not l.startswith("#")), delimiter="\t"):
        if r[0] == "entry":
            yield r[1], r[2], json.loads(r[3])


def item_for(k, head, senses):
    cand = [(i, s) for i, s in enumerate(senses, 1) if s["sources"] == ["CEDICT"]]
    if not cand:
        return None, []
    full = " / ".join(s["gloss"] for s in senses)
    lst = "\n".join(f"{k}.{j}. {s['gloss']}" for j, (_, s) in enumerate(cand, 1))
    return f"{k}. Headword: {head}\nFull entry: {full}\nTo check:\n{lst}", [i for i, _ in cand]


def cache_path(model, effort, text):
    key = hashlib.sha256(json.dumps([model, effort, PROMPT, text]).encode()).hexdigest()[:24]
    d = os.path.join(OUT, model + "-" + effort)
    os.makedirs(d, exist_ok=True)
    return key, os.path.join(d, key + ".json")


def params(model, effort, text):
    return dict(model=model, max_tokens=8000, system=[{"type": "text", "text": PROMPT, "cache_control": {"type": "ephemeral"}}],
                messages=[{"role": "user", "content": text}], output_config={"effort": effort})


def record(m):
    reply = "".join(b.text for b in m.content if b.type == "text")
    v = None
    try:
        v = json.loads(reply[reply.index("{"):reply.rindex("}") + 1])["verdicts"]
    except (ValueError, KeyError):
        v = None
    rec = {"verdicts": v, "reply": reply if v is None else None,
           "usage": [m.usage.input_tokens, m.usage.output_tokens, m.usage.cache_read_input_tokens or 0,
                     m.usage.cache_creation_input_tokens or 0]}
    return rec


def ask(client, model, text, effort):
    key, path = cache_path(model, effort, text)
    if os.path.exists(path):
        return json.load(open(path))
    rec = record(client.messages.create(**params(model, effort, text)))
    json.dump(rec, open(path, "w"), ensure_ascii=False)
    return rec


def run_batch(client, model, effort, texts):
    """The uncached requests through the Message Batches API (half price)."""
    import time
    todo = {}
    for t in texts:
        key, path = cache_path(model, effort, t)
        if not os.path.exists(path):
            todo[key] = (t, path)
    if not todo:
        return
    b = client.messages.batches.create(requests=[{"custom_id": k, "params": params(model, effort, t)}
                                                 for k, (t, _) in todo.items()])
    print("batch", b.id, len(todo), flush=True)
    while client.messages.batches.retrieve(b.id).processing_status != "ended":
        time.sleep(60)
    for res in client.messages.batches.results(b.id):
        if res.result.type == "succeeded":
            rec = record(res.result.message)
            rec["batch"] = True
            json.dump(rec, open(todo[res.custom_id][1], "w"), ensure_ascii=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="claude-sonnet-5-5")
    ap.add_argument("--effort", default="low")
    ap.add_argument("--chars-file", help="only these headwords (whitespace-separated)")
    ap.add_argument("--scope", default="common", help="common: characters ranked <= 3,000 and words")
    ap.add_argument("--group", type=int, default=15)
    ap.add_argument("--out", required=True)
    ap.add_argument("--estimate", action="store_true")
    ap.add_argument("--batch", action="store_true", help="send uncached requests through the Batch API")
    a = ap.parse_args()
    want = set(open(a.chars_file).read().split()) if a.chars_file else None
    import sqlite3
    rank = dict(sqlite3.connect(os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite"))
                .execute("SELECT ch, rank FROM chars"))
    items = []
    for head, simp, senses in entries():
        if want is not None:
            if head not in want:
                continue
        elif len(head) == 1 and not 0 < (rank.get(simp) or rank.get(head) or 0) <= 3000:
            continue
        if any(s["sources"] == ["CEDICT"] for s in senses):
            items.append((head, senses))
    groups = [items[i:i + a.group] for i in range(0, len(items), a.group)]
    jobs = []
    for g in groups:
        parts, idx = [], []
        for k, (head, senses) in enumerate(g, 1):
            t, ix = item_for(k, head, senses)
            parts.append(t)
            idx.append(ix)
        jobs.append((g, "\n\n".join(parts), idx))
    print(f"{len(items)} entries in {len(jobs)} requests")
    if a.estimate:
        return
    import anthropic
    client = anthropic.Anthropic()
    if a.batch:
        run_batch(client, a.model, a.effort, [t for _, t, _ in jobs])
    with cf.ThreadPoolExecutor(6) as ex:
        res = list(ex.map(lambda j: ask(client, a.model, j[1], a.effort), jobs))
    price = {"claude-haiku-5-5": (0.10, 0.50), "claude-sonnet-5-5": (2.0, 10.0), "claude-opus-5-5": (4.0, 20.0)}[a.model]
    u = [sum(r["usage"][k] for r in res) for k in range(4)]
    usd = (u[0] + 0.1 * u[2] + 1.25 * u[3]) / 1e6 * price[0] + u[1] / 1e6 * price[1]
    if a.batch:
        usd /= 2
    bad = 0
    with open(a.out, "w") as f:
        for (g, t, idx), r in zip(jobs, res):
            if r["verdicts"] is None:
                bad += 1
                continue
            for v in r["verdicts"]:
                try:
                    k, j = (int(x) for x in str(v["id"]).split("."))
                    head, senses = g[k - 1]
                    i = idx[k - 1][j - 1]
                except (ValueError, IndexError, KeyError):
                    continue
                f.write(f"{head}\t{i}\t{senses[i - 1]['gloss']}\t{v['v']}\n")
    print(f"{len(jobs)} requests ({bad} unparsed); tokens in {u[0]:,} out {u[1]:,} cache read {u[2]:,}; "
          f"${usd:.3f}" + (" (batch price)" if a.batch else " at standard price"))


main()
