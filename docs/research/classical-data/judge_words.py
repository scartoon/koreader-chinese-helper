"""#66: corpus-wide judgments with Claude Haiku, to be spot-checked by hand.

    ANTHROPIC_API_KEY=... python judge_words.py ROOT split    # each CC-CEDICT word occurrence:
                                                            # one word here, or not a word here?
    ANTHROPIC_API_KEY=... python judge_words.py ROOT mislead  # the same occurrences: would the modern senses mislead?
    ANTHROPIC_API_KEY=... python judge_words.py ROOT adds     # each CC-CEDICT word with literary senses:
                                                            # does one add a meaning CC-CEDICT lacks?
Replies are cached in build/classical/words/cache/ (key: model, prompt, input),
results go to build/classical/words/<mode>.tsv.
"""
import collections, concurrent.futures as cf, csv, hashlib, json, os, re, sqlite3, sys

ROOT, MODE = sys.argv[1], sys.argv[2]
OUT = os.path.join(ROOT, "build", "classical", "words")
CACHE = os.path.join(OUT, "cache")
DB = os.path.join(ROOT, "chinesehelper.koplugin", "data", "chinesehelper.sqlite")
MODEL = "claude-haiku-5-5"
HAN = r"㐀-鿿"

PROMPT_SPLIT = """You check a classical Chinese reading aid. A pop-up dictionary lists every dictionary word found around the tapped character, without segmenting the text. In classical Chinese, a string that is one word in modern Chinese is often two separate words (妻子 "wife and children", not "wife"; 可以 "can use it to", 可 + 以; 所以 "that by which"), or it crosses a word boundary (in 賢相通其謀, 相通 is not a word: 賢相 + 通).

You get a passage, a string from it (marked 【】 in the passage) and the modern dictionary's senses of that string. Decide how the string is used in this passage:
- "word": it is one word here, and one of the given senses fits.
- "word-other": it is one word here, but in a sense the dictionary doesn't give.
- "split": it is not one word here (two or more separate words, or it crosses a word boundary).

Reply with JSON only: {"verdict": "word" | "word-other" | "split", "why": "a few words"}"""

PROMPT_MISLEAD = """You check a classical Chinese reading aid. A pop-up dictionary lists every modern dictionary word found around the tapped character, without segmenting the text. In classical Chinese a string that is one word in modern Chinese can be two separate words, or cross a word boundary, so that its modern senses mislead: 妻子 read as "wife" where it means "wife and children"; 可以 read as "can" where it is 可 + 以 "can use it to"; 所以 read as "therefore" where it means "that by which"; 之上 read as "above" in 丹之上願 ("Dan's highest wish"); 夫君 read as "husband" in 夫君子能勤小物 (夫 + 君子).

You get a passage, a string from it (marked 【】) and the string's modern dictionary senses. Would a reader who takes one of these modern senses for the string misunderstand this passage?
- "fits": one of the senses gives the right meaning here, even if the string is technically two classical words (不知 "not know", 可謂 "can be called", 天下 "the world").
- "mislead": none of the senses gives the meaning here, because the string isn't one word in this passage (two words, or it crosses a word boundary).
- "other-sense": the string is one word here, but in a sense none of the given senses has.

Reply with JSON only: {"verdict": "fits" | "mislead" | "other-sense", "why": "a few words"}"""

PROMPT_ADDS = """You compare two dictionaries for a classical Chinese reading aid. For one Chinese word you get the senses of a modern dictionary (CC-CEDICT) and the literary or classical senses of other dictionaries.

Does any literary sense give a meaning that none of the modern senses gives (not just other wording, a narrower or wider version, or an extra example)? Reply with JSON only:
{"adds": true | false, "senses": ["the literary senses that add a meaning, as given"]}"""


def cedict():
    out = collections.defaultdict(list)
    for simp, trad, pinyin, defs in sqlite3.connect(DB).execute(
            "SELECT simp, trad, pinyin, defs FROM entries WHERE length(simp) >= 2"):
        out[trad].append(f"{pinyin}: {defs}")
        if simp != trad:
            out.setdefault(simp, out[trad])
    return out


def ask(client, prompt, text):
    key = hashlib.sha256(json.dumps([MODEL, prompt, text]).encode()).hexdigest()[:24]
    path = os.path.join(CACHE, key + ".json")
    if os.path.exists(path):
        return json.load(open(path))
    msg = client.messages.create(model=MODEL, max_tokens=400, system=prompt, thinking={"type": "disabled"},
                                 messages=[{"role": "user", "content": text}])
    reply = "".join(b.text for b in msg.content if b.type == "text").strip().strip("`").removeprefix("json").strip()
    try:
        res = json.loads(reply[reply.index("{"):reply.rindex("}") + 1])
    except ValueError:
        res = {"unparsed": reply}
    res["usage"] = [msg.usage.input_tokens, msg.usage.output_tokens]
    json.dump(res, open(path, "w"), ensure_ascii=False)
    return res


def main():
    import anthropic
    client = anthropic.Anthropic()
    os.makedirs(CACHE, exist_ok=True)
    ced = cedict()
    jobs = []
    if MODE in ("split", "mislead"):
        prompt = PROMPT_SPLIT if MODE == "split" else PROMPT_MISLEAD
        for name in sorted(os.listdir(os.path.join(ROOT, "build", "classical", "texts"))):
            text = open(os.path.join(ROOT, "build", "classical", "texts", name)).read()
            text = "\n".join(l for l in text.split("\n") if not l.startswith("#"))
            for m in re.finditer(f"[{HAN}]+", text):
                run, base = m.group(0), m.start()
                for i in range(len(run)):
                    for j in range(i + 2, min(len(run), i + 8) + 1):
                        w = run[i:j]
                        if w in ced:
                            a, b = base + i, base + j
                            passage = text[max(0, a - 25):a].split("\n")[-1] + "【" + w + "】" + text[b:b + 25].split("\n")[0]
                            jobs.append(((name, a, w), f"Passage: {passage}\nString: {w}\nModern senses: {' | '.join(ced[w])}"))
    else:
        prompt = PROMPT_ADDS
        lit = collections.defaultdict(list)
        for r in csv.DictReader(open(os.path.join(OUT, "literary_words.tsv")), delimiter="\t"):
            lit[r["trad"]].append(f"[{r['source']}] {r['sense']}")
        words = [r["word"] for r in csv.DictReader(open(os.path.join(OUT, "corpus.tsv")), delimiter="\t")
                 if r["cedict"] == "1" and r["literary"] == "1"]
        for w in words:
            jobs.append(((w,), f"Word: {w}\nModern senses: {' | '.join(ced[w])}\nLiterary senses:\n" +
                         "\n".join(lit[w] if w in lit else lit.get(w, []))))
    print(len(jobs), "requests")
    with cf.ThreadPoolExecutor(8) as ex:
        results = list(ex.map(lambda j: (j[0], j[1], ask(client, prompt, j[1])), jobs))
    tin = sum(r["usage"][0] for *_, r in results)
    tout = sum(r["usage"][1] for *_, r in results)
    print(f"tokens {tin:,} in, {tout:,} out, ${tin / 1e6 * 0.10 + tout / 1e6 * 0.50:.2f} (cached replies count again)")
    with open(os.path.join(OUT, MODE + ".tsv"), "w") as f:
        for k, text, r in results:
            f.write("\t".join(map(str, k)) + "\t" + json.dumps({x: y for x, y in r.items() if x != "usage"}, ensure_ascii=False)
                    + "\t" + text.replace("\n", " ⏎ ") + "\n")


main()
