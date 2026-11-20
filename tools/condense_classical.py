#!/usr/bin/env python3
"""Research prototype for #49: condense each character's collated classical
senses (tools/collate_classical.py) into at most five English senses with
Claude Haiku, for the Classical dictionary.

    ANTHROPIC_API_KEY=... .venv/bin/python tools/condense_classical.py --chars 之其而 [--variant bundled|local|both]
    .venv/bin/python tools/condense_classical.py --chars-file build/classical/prototype_chars.txt --estimate

Reads build/classical/collated.tsv. Each input line is numbered and each
sense cites the lines it came from (its sources follow from those), so
every sense can be checked against its input. Writes build/classical/condensed.jsonl,
one line per (character, variant): the condensed senses, the raw collated
input (kept for a tap-to-expand view), token usage. Every response is
cached in build/classical/condense_cache/, keyed by the model, the prompt,
the variant and the input text, so a rerun never calls the API again for
an unchanged input.

Variants: "bundled" leaves MOE out (its BY-ND licence keeps it out of the
release); "local" includes MOE, for a file the user builds themselves.

The prompt is tools/condense_classical_prompt.txt. Model claude-haiku-5-5,
thinking off. Haiku 5.5 rejects a non-default temperature (400), so none is
sent; the cache keeps reruns stable instead.
"""
import argparse
import collections
import csv
import hashlib
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "build", "classical")
PROMPT = os.path.join(ROOT, "tools", "condense_classical_prompt.txt")
MODEL = "claude-haiku-5-5"
# USD per million tokens (claude-haiku-5-5, prompts under 100K tokens); the
# Batch API halves both.
PRICE_IN, PRICE_OUT = 0.10, 0.50
LABEL = {"cedict": "CEDICT", "wikt": "Wikt", "cn": "CN", "unihan": "Unihan", "moe": "MOE"}
ORDER = ["cedict", "wikt", "cn", "unihan", "moe"]


def load_collated():
    by = collections.defaultdict(list)
    for r in csv.DictReader(open(os.path.join(OUT, "collated.tsv")), delimiter="\t"):
        if r["source"] == "unihan" and r["tag"] != "rare":
            continue      # Unihan only for characters outside the 3,000 most frequent
        by[r["trad"]].append(r)
    return by


def input_text(ch, rows, variant):
    lines, seen = [], set()
    simp = rows[0]["simp"] if rows else ch
    for src in ORDER:
        if src == "moe" and variant == "bundled":
            continue
        for r in rows:
            if r["source"] != src:
                continue
            sense = r["sense"].split(" ‖ ")[0].strip()   # MOE: the definition, not its 書證 quote
            key = (src, r["reading"], sense)
            if not sense or key in seen:
                continue
            seen.add(key)
            reading = f" {r['reading']}" if r["reading"] else ""
            lines.append(f"[{LABEL[src]}]{reading} {sense}")
    if not lines:
        return None
    head = f"Character: {ch}" + (f" (simplified: {simp})" if simp != ch else "")
    return head + "\n" + "\n".join(f"{k}. {line}" for k, line in enumerate(lines, 1))


def add_sources(senses, text):
    """The sources of each sense, from the input lines it cites."""
    src = {}
    for line in text.split("\n")[1:]:
        num, rest = line.split(". ", 1)
        src[int(num)] = rest[1:rest.index("]")]
    for s in senses:
        cited = [n for n in s.get("lines", []) if isinstance(n, int)]
        s["sources"] = sorted({src[n] for n in cited if n in src})
        s["bad_lines"] = [n for n in cited if n not in src]
    return senses


def cache_path(key):
    return os.path.join(OUT, "condense_cache", key + ".json")


def estimate_tokens(text):
    # Rough: CJK characters about one token each, other text about 4 characters per token.
    cjk = sum(1 for c in text if ord(c) > 0x2e80)
    return cjk + (len(text) - cjk) / 4


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--chars", default="")
    ap.add_argument("--chars-file")
    ap.add_argument("--variant", default="both", choices=["bundled", "local", "both"])
    ap.add_argument("--estimate", action="store_true", help="print the token and cost estimate, call nothing")
    ap.add_argument("--all", action="store_true", help="every character in collated.tsv (estimate only)")
    args = ap.parse_args()
    prompt = open(PROMPT).read()
    by = load_collated()
    chars = list(args.chars)
    if args.chars_file:
        chars += [c for c in open(args.chars_file).read() if not c.isspace()]
    if args.all:
        chars = list(by)
    chars = list(dict.fromkeys(chars))
    variants = ["bundled", "local"] if args.variant == "both" else [args.variant]
    jobs = []
    for ch in chars:
        for v in variants:
            text = input_text(ch, by.get(ch, []), v)
            if text:
                key = hashlib.sha256(json.dumps([MODEL, prompt, v, text]).encode()).hexdigest()[:24]
                jobs.append((ch, v, text, key))
    est_in = sum(estimate_tokens(prompt) + estimate_tokens(t) for _, _, t, _ in jobs)
    est_out = 60 * 5 * len(jobs) / 2     # about 150 tokens for a typical five-sense JSON reply
    cost = est_in / 1e6 * PRICE_IN + est_out / 1e6 * PRICE_OUT
    cached = sum(os.path.exists(cache_path(k)) for *_, k in jobs)
    print(f"{len(jobs)} requests ({cached} cached), ~{est_in:,.0f} input + ~{est_out:,.0f} output tokens, "
          f"~${cost:.2f} (Batch API ~${cost / 2:.2f})")
    if args.estimate:
        return
    import anthropic
    client = anthropic.Anthropic()        # the key comes from ANTHROPIC_API_KEY only
    os.makedirs(os.path.join(OUT, "condense_cache"), exist_ok=True)
    used_in = used_out = 0
    with open(os.path.join(OUT, "condensed.jsonl"), "a") as out:
        for n, (ch, v, text, key) in enumerate(jobs, 1):
            path = cache_path(key)
            if os.path.exists(path):
                rec = json.load(open(path))
            else:
                try:
                    msg = client.messages.create(
                        model=MODEL, max_tokens=2000, system=prompt,
                        thinking={"type": "disabled"},
                        messages=[{"role": "user", "content": text}])
                except anthropic.RateLimitError as e:
                    print("rate limited, stopping:", e.status_code, file=sys.stderr)
                    break
                except anthropic.APIStatusError as e:
                    print(f"{ch} {v}: API error {e.status_code}: {e.message}", file=sys.stderr)
                    continue
                except anthropic.APIConnectionError as e:
                    print(f"{ch} {v}: connection error: {e}", file=sys.stderr)
                    continue
                reply = "".join(b.text for b in msg.content if b.type == "text").strip()
                if reply.startswith("```"):
                    reply = reply.strip("`").removeprefix("json").strip()
                try:
                    senses = add_sources(json.loads(reply)["senses"], text)
                except (ValueError, KeyError, TypeError):
                    senses, reply = None, reply
                rec = {"char": ch, "variant": v, "model": MODEL, "input": text, "senses": senses,
                       "raw_reply": reply if senses is None else None, "stop_reason": msg.stop_reason,
                       "usage": {"input": msg.usage.input_tokens, "output": msg.usage.output_tokens}}
                json.dump(rec, open(path, "w"), ensure_ascii=False)
                used_in += msg.usage.input_tokens
                used_out += msg.usage.output_tokens
            out.write(json.dumps(rec, ensure_ascii=False) + "\n")
            if n % 25 == 0:
                print(f"{n}/{len(jobs)}", file=sys.stderr)
    print(f"this run: {used_in:,} input + {used_out:,} output tokens, "
          f"${used_in / 1e6 * PRICE_IN + used_out / 1e6 * PRICE_OUT:.4f}")


if __name__ == "__main__":
    main()
