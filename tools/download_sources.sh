#!/bin/sh
# Download the candidate fallback dictionaries into build/sources/ (git-ignored),
# for tools/measure_fallback.py. Resumable; about 1.3 GB in all.
#
#   wiktionary/  kaikki.org's wiktextract of English Wiktionary, Chinese (CC BY-SA 4.0)
#   wikipedia/   zhwiki page, langlinks, page_props, categorylinks, linktarget dumps (CC BY-SA 4.0)
#   moe/         g0v moedict-data dict-revised.json.xz: MOE 重編國語辭典修訂本
#                (CC BY-ND 3.0 TW: never committed or bundled)
#   naer/        NAER terminology CSVs listed in the data.gov.tw catalogue
#                (Open Government Data License v1.0, compatible with CC BY 4.0)
#   jieba/       jieba's big dictionary (MIT), for segmenting the measurement corpus
set -e
cd "$(dirname "$0")/.."
PY=python3
[ -x .venv/bin/python ] && PY=.venv/bin/python
mkdir -p build/sources/wiktionary build/sources/wikipedia build/sources/moe build/sources/naer build/sources/jieba
cd build/sources
UA="koreader-chinese-helper dictionary build"
get() { curl -sSL -A "$UA" -C - --retry 3 -o "$2" "$1" && echo "ok $2"; }

get https://kaikki.org/dictionary/Chinese/kaikki.org-dictionary-Chinese.jsonl.gz wiktionary/kaikki-Chinese.jsonl.gz &
get https://raw.githubusercontent.com/g0v/moedict-data/main/dict-revised.json.xz moe/dict-revised.json.xz &
get https://github.com/fxsjy/jieba/raw/master/extra_dict/dict.txt.big jieba/dict.txt.big &
for t in page langlinks page_props categorylinks linktarget; do
  get https://dumps.wikimedia.org/zhwiki/latest/zhwiki-latest-$t.sql.gz wikipedia/zhwiki-latest-$t.sql.gz
done &
wait

# NAER: every 國家教育研究院 terminology (名詞) dataset in the data.gov.tw catalogue.
[ -s naer/catalog.csv ] || get https://data.gov.tw/datasets/export/csv naer/catalog.csv
"$PY" - <<'EOF'
import csv
csv.field_size_limit(10**9)
rows = csv.DictReader(open("naer/catalog.csv", encoding="utf-8-sig"))
out = []
for r in rows:
    if "國家教育研究院" in r["提供機關"] and "名詞" in r["資料集名稱"]:
        for u in r["資料下載網址"].split(";"):
            if u.strip().lower().endswith(".csv"):
                out.append(f"{r['資料集名稱']}\t{u.strip()}")
open("naer/urls.tsv", "w", encoding="utf-8").write("\n".join(out) + "\n")
print(f"naer: {len(out)} CSV files listed")
EOF
n=0
: > naer/files.tsv.tmp
while IFS="$(printf '\t')" read -r name url; do
  n=$((n+1)); f="naer/$(printf '%03d' $n).csv"
  [ -s "$f" ] || curl -sSL -A "$UA" --retry 3 -o "$f" "$url"
  printf '%s\t%s\n' "$f" "$name" >> naer/files.tsv.tmp
done < naer/urls.tsv
mv naer/files.tsv.tmp naer/files.tsv
echo "ok naer $n files"
