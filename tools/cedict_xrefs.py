#!/usr/bin/env python3
"""CC-CEDICT entries whose only senses are cross-references (#61): 贤惠's
single sense is "variant of 賢慧|贤慧[xian2 hui4]", so its popup says nothing
about the word. The build resolves such entries to the word they point to and
stores that word's senses beside the entry (build_db.py: the entries table's
xref_* columns), for the popup to show under CC-CEDICT's own line.

    python3 tools/cedict_xrefs.py --report [--cedict build/cedict_1_0_ts_utf-8_mdbg.txt.gz]

writes build/cedict-xrefs-report.txt: cross-reference-only entries counted by
pattern, ~10 examples each, and how the resolver does on them.

Resolved patterns: every "... variant of", "see", "same as", "also written".
"see also", "used in" and "abbr. for" are left alone (a "used in" on a single
character can point to many words). The target is found by its forms and its
pinyin; when the pinyin matches none of its rows, the target's only row is
taken if it has exactly one. A target that is itself cross-reference-only is
followed, up to MAX_HOPS hops.
"""
import argparse
import gzip
import os
import re
import sys
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINE_RE = re.compile(r"^(\S+) (\S+) \[([^\]]*)\] /(.*)/\s*$")
# One reference: 賢慧|贤慧[xian2 hui4] or 東西[dong1 xi5] (as build_db.XREF_RE).
FORM = r"[0-9A-Za-z]*(?:[^\x00-\x7f\s\[\]|,;:()/][0-9A-Za-z]*)+"
REF = rf"({FORM})(?:\|({FORM}))?\[([A-Za-z0-9:, ·]+)\]"
REF_RE = re.compile(REF)
# A cross-reference sense: an optional label ("(old)", "(Tw)"), the pattern,
# then one or more references, optionally a trailing note in parentheses.
KIND = r"(?P<kind>(?:[a-z][a-z-]* )*variant of|see also|see|same as|also written|used in|abbr\. for)"
XREF_SENSE_RE = re.compile(
    rf"^(?:\([^()]*\) *)?{KIND} (?P<refs>{FORM}(?:\|{FORM})?\[[A-Za-z0-9:, ·]+\]"
    rf"(?:(?: *,| *;| and| or|,? also| /)? *{FORM}(?:\|{FORM})?\[[A-Za-z0-9:, ·]+\])*)"
    rf"(?: *\([^()]*\))?\.?$")
# Senses that are neither a meaning nor a reference: measure words, other
# pronunciations. They don't stop an entry counting as cross-reference-only.
NEUTRAL_RE = re.compile(r"^(CL:|(?:Taiwan|Tw|also) pr\. )")
RESOLVED_KINDS = ("variant of", "see", "same as", "also written")
MAX_HOPS = 3


def kind_group(kind):
    """The report's grouping: 'variant of', 'old variant of', '… variant of'
    (erhua, archaic, ...), and the other kinds as they are."""
    if kind in ("variant of", "old variant of"):
        return kind
    if kind.endswith("variant of"):
        return "… variant of"
    return kind


def resolvable(kind):
    return kind.endswith("variant of") or kind in RESOLVED_KINDS


def parse_xref(sense):
    """'variant of 賢慧|贤慧[xian2 hui4]' -> ('variant of', [('賢慧', '贤慧',
    'xian2 hui4')]); None when the sense is not only a cross-reference.
    A reference with one form gives it as both traditional and simplified."""
    m = XREF_SENSE_RE.match(sense.strip())
    if not m:
        return None
    refs = [(a, b or a, py) for a, b, py in REF_RE.findall(m.group("refs"))]
    return m.group("kind"), refs


def norm_py(py):
    """Pinyin compared case-insensitively, ü however written ("Lu : 3" in a
    few references)."""
    py = re.sub(r" *: *", ":", py)
    return " ".join(py.replace("u:", "v").replace("ü", "v").lower().split())


class Resolver:
    """entries: (trad, simp, numbered pinyin, [raw senses]) in CC-CEDICT's order."""

    def __init__(self, entries):
        self.entries = entries
        self.by_form = defaultdict(list)
        for i, (trad, simp, _, _) in enumerate(entries):
            self.by_form[simp].append(i)
            if trad != simp:
                self.by_form[trad].append(i)
        self.xrefs = [self.xref_only(e[3]) for e in entries]

    @staticmethod
    def xref_only(senses):
        """The entry's cross-references [(kind, refs)] when every sense is one
        (measure-word and pronunciation senses aside), else None."""
        out = []
        for s in senses:
            if NEUTRAL_RE.match(s):
                continue
            x = parse_xref(s)
            if x is None:
                return None
            out.append(x)
        return out or None

    def find(self, trad, simp, py, exclude=()):
        """The rows for reference trad|simp[py], never one in `exclude` (the
        entry itself: 㑺|俊 is "old variant of 俊"): (rows, how) with how
        'exact' or 'only' (the target's one row, its pinyin differing), or
        (None, reason) with reason 'missing' / 'ambiguous'."""
        cands = [i for i in self.by_form.get(simp, []) + self.by_form.get(trad, []) if i not in exclude]
        both = [i for i in cands if self.entries[i][0] == trad and self.entries[i][1] == simp]
        rows = list(dict.fromkeys(both or [i for i in cands if self.entries[i][1] == simp] or cands))
        if not rows:
            return None, "missing"
        want = norm_py(py)
        exact = [i for i in rows if norm_py(self.entries[i][2]) == want]
        if exact:
            return exact, "exact"
        if len(rows) == 1:
            return rows, "only"
        return None, "ambiguous"

    def target(self, i):
        """Entry i's target: (status, rows) with status 'exact' / 'only' (the
        first reference, see find) or 'chain' (reached through other
        cross-reference-only entries) and rows the target's rows (same forms
        and pinyin; their senses are the definitions to show), or (reason,
        None) with reason 'kind' (only unresolved kinds), 'several'
        (references to different words), 'missing', 'ambiguous', 'cycle',
        'too-long'."""
        seen = {i}
        cur, status = i, None
        for hop in range(MAX_HOPS + 1):
            refs = []
            for kind, rs in self.xrefs[cur]:
                if resolvable(kind):
                    refs += [r for r in rs if r not in refs]
            if not refs:
                # A chain ending on a "see also" / "used in" entry ends there.
                return ("kind", None) if hop == 0 else (status, [cur])
            if hop == MAX_HOPS:
                return "too-long", None
            targets = {}
            for trad, simp, py in refs:
                rows, how = self.find(trad, simp, py, exclude={cur})
                if rows is None:
                    return how, None
                targets[tuple(rows)] = how
            if len(targets) > 1:  # 伭: variant of 玄 and of 悬
                return "several", None
            (rows, how), = targets.items()
            status = how if hop == 0 else "chain"
            plain = [r for r in rows if self.xrefs[r] is None]
            if plain:
                return status, plain
            if any(r in seen for r in rows):
                return "cycle", None
            seen.update(rows)
            cur = rows[0]
        return "too-long", None


def read_raw(path):
    entries = []
    op = gzip.open(path, "rt", encoding="utf-8") if path.endswith(".gz") else open(path, encoding="utf-8")
    with op as f:
        for line in f:
            if line.startswith("#"):
                continue
            m = LINE_RE.match(line.strip())
            if m:
                trad, simp, py, defs = m.groups()
                entries.append((trad, simp, py, [s for s in defs.split("/") if s.strip()]))
    return entries


def report(path, out):
    entries = read_raw(path)
    res = Resolver(entries)
    groups = defaultdict(list)
    outcome = defaultdict(Counter)
    resolved_examples = defaultdict(list)
    unresolved_examples = defaultdict(list)
    # "used in" / "abbr. for": how many have targets with plain definitions.
    plain_targets = Counter()
    for i, e in enumerate(entries):
        xs = res.xrefs[i]
        if xs is None:
            continue
        kinds = {kind_group(k) for k, _ in xs}
        group = kinds.pop() if len(kinds) == 1 else "mixed: " + " + ".join(sorted({kind_group(k) for k, _ in xs}))
        groups[group].append(i)
        status, rows = res.target(i)
        outcome[group][status] += 1
        line = f"{e[0]} {e[1]} [{e[2]}] /{'/'.join(e[3])}/"
        if rows is not None:
            if len(resolved_examples[status]) < 10:
                t = entries[rows[0]]
                resolved_examples[status].append(f"{line}\n      -> {t[1]} [{t[2]}] /{'/'.join(t[3])[:120]}/")
        elif status not in ("kind",):
            if len(unresolved_examples[status]) < 10:
                unresolved_examples[status].append(line)
        if group in ("used in", "abbr. for"):
            refs = [r for _, rs in xs for r in rs]
            if len(refs) == 1:
                rows2, _ = res.find(*refs[0], exclude={i})
                if rows2 and res.xrefs[rows2[0]] is None:
                    plain_targets[group] += 1
    with open(out, "w", encoding="utf-8") as f:
        f.write(f"CC-CEDICT {path}: {len(entries)} entries, "
                f"{sum(len(v) for v in groups.values())} cross-reference-only\n\n")
        f.write("Cross-reference-only entries by pattern, and the resolver's outcome:\n")
        for g, idx in sorted(groups.items(), key=lambda kv: -len(kv[1])):
            oc = ", ".join(f"{k} {v}" for k, v in outcome[g].most_common())
            f.write(f"  {len(idx):6d}  {g}   [{oc}]\n")
        f.write(f"\n'used in' / 'abbr. for' with one target that has plain definitions: {dict(plain_targets)}\n")
        total = Counter()
        for g in outcome:
            total.update(outcome[g])
        f.write(f"\nOverall outcome: {dict(total.most_common())}\n")
        for g, idx in sorted(groups.items(), key=lambda kv: -len(kv[1])):
            f.write(f"\n== {g} ({len(idx)})\n")
            for i in idx[:: max(1, len(idx) // 10)][:10]:
                e = entries[i]
                f.write(f"  {e[0]} {e[1]} [{e[2]}] /{'/'.join(e[3])}/\n")
        for status, ex in resolved_examples.items():
            f.write(f"\n== resolved, {status}\n")
            for x in ex:
                f.write(f"  {x}\n")
        for status, ex in unresolved_examples.items():
            f.write(f"\n== unresolved, {status}\n")
            for x in ex:
                f.write(f"  {x}\n")
    return groups, outcome


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cedict", default=os.path.join(ROOT, "build", "cedict_1_0_ts_utf-8_mdbg.txt.gz"))
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "cedict-xrefs-report.txt"))
    args = ap.parse_args()
    if not args.report:
        ap.print_help()
        return
    report(args.cedict, args.out)
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    sys.exit(main())
