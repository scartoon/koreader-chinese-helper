#!/usr/bin/env python3
"""Pull the EPUBs from a USB-connected Android device and extract their Chinese
text, for measuring dictionary coverage on real reading material.

    python3 tools/fetch_books.py                      # /sdcard/Books -> build/books, build/corpus
    python3 tools/fetch_books.py --device-dir /sdcard/Books --min-han 20000

Everything goes into build/ (git-ignored): the books are the reader's own and
are never committed.

  build/books/<n>.epub      the pulled files (re-pulled only when the size changed)
  build/corpus/<n>.txt      one paragraph per line, in reading order (spine)
  build/corpus/index.tsv    n, Han characters, share of Han among non-space
                            characters, kept (1/0), device file name

A book is kept when it has at least --min-han Han characters and Han is at
least --min-share of its non-space characters: Chinese books, not English
ones quoting a few characters. Formats other than EPUB are listed and skipped.
"""
import argparse
import html
import os
import posixpath
import re
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOOKS = os.path.join(ROOT, "build", "books")
CORPUS = os.path.join(ROOT, "build", "corpus")

HAN_RE = re.compile(r"[㐀-䶿一-鿿豈-﫿\U00020000-\U0003134f]")
BLOCK_RE = re.compile(r"</(?:p|div|h[1-6]|li|blockquote|tr|dd|dt)>|<br\s*/?>", re.I)


def adb(*args):
    return subprocess.run(["adb", *args], check=True, capture_output=True, text=True).stdout


def device_listing(directory):
    """[(name, size)] of the files in `directory` on the device."""
    out = adb("shell", f"cd '{directory}' && ls -l")
    files = []
    for line in out.splitlines():
        parts = line.split(None, 7)
        if len(parts) == 8 and line.startswith("-"):
            files.append((parts[7], int(parts[4])))
    return files


def spine_documents(z):
    """The book's content documents in reading order (OPF spine), falling back
    to every (X)HTML file in name order."""
    try:
        container = z.read("META-INF/container.xml").decode("utf-8", "ignore")
        opf_path = re.search(r'full-path="([^"]+)"', container).group(1)
        opf = z.read(opf_path).decode("utf-8", "ignore")
        base = posixpath.dirname(opf_path)
        manifest = {m.group(1): m.group(2) for m in
                    re.finditer(r'<item\b[^>]*?\bid="([^"]+)"[^>]*?\bhref="([^"]+)"', opf)}
        manifest.update({m.group(2): m.group(1) for m in
                         re.finditer(r'<item\b[^>]*?\bhref="([^"]+)"[^>]*?\bid="([^"]+)"', opf)})
        docs = []
        for m in re.finditer(r'<itemref\b[^>]*?\bidref="([^"]+)"', opf):
            href = manifest.get(m.group(1))
            if href:
                path = posixpath.normpath(posixpath.join(base, html.unescape(href).split("#")[0]))
                if path in z.namelist():
                    docs.append(path)
        if docs:
            return docs
    except (KeyError, AttributeError):
        pass
    return sorted(n for n in z.namelist() if n.lower().endswith((".xhtml", ".html", ".htm")))


def paragraphs(path):
    with zipfile.ZipFile(path) as z:
        for name in spine_documents(z):
            text = z.read(name).decode("utf-8", "ignore")
            text = re.sub(r"<(script|style|head)\b[^>]*>.*?</\1>", "", text, flags=re.S | re.I)
            for block in BLOCK_RE.split(text):
                p = html.unescape(re.sub(r"<[^>]+>", "", block))
                p = re.sub(r"\s+", " ", p).strip()
                if p:
                    yield p


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--device-dir", default="/sdcard/Books")
    ap.add_argument("--min-han", type=int, default=20000)
    ap.add_argument("--min-share", type=float, default=0.5)
    args = ap.parse_args()
    os.makedirs(BOOKS, exist_ok=True)
    os.makedirs(CORPUS, exist_ok=True)

    files = device_listing(args.device_dir)
    epubs = sorted((n, s) for n, s in files if n.lower().endswith(".epub"))
    others = sorted(n for n, _ in files if n.lower().endswith((".mobi", ".azw3", ".azw", ".fb2", ".txt", ".pdf")))
    print(f"{args.device_dir}: {len(epubs)} EPUBs; skipped (not EPUB): {len(others)}")
    rows = []
    for k, (name, size) in enumerate(epubs, 1):
        local = os.path.join(BOOKS, f"{k:03d}.epub")
        if not (os.path.exists(local) and os.path.getsize(local) == size):
            adb("pull", f"{args.device_dir}/{name}", local)
        try:
            paras = list(paragraphs(local))
        except zipfile.BadZipFile:
            rows.append((k, 0, 0.0, 0, name))
            continue
        han = sum(len(HAN_RE.findall(p)) for p in paras)
        nonspace = sum(len(p.replace(" ", "")) for p in paras) or 1
        share = han / nonspace
        keep = han >= args.min_han and share >= args.min_share
        if keep:
            with open(os.path.join(CORPUS, f"{k:03d}.txt"), "w", encoding="utf-8") as f:
                f.write("\n".join(paras) + "\n")
        rows.append((k, han, share, int(keep), name))
    with open(os.path.join(CORPUS, "index.tsv"), "w", encoding="utf-8") as f:
        f.write("n\than\tshare\tkept\tfile\n")
        for k, han, share, keep, name in rows:
            f.write(f"{k:03d}\t{han}\t{share:.3f}\t{keep}\t{name}\n")
        for name in others:
            f.write(f"-\t-\t-\tskipped (format)\t{name}\n")
    kept = [r for r in rows if r[3]]
    print(f"kept {len(kept)} Chinese books, {sum(r[1] for r in kept):,} Han characters -> build/corpus/")


if __name__ == "__main__":
    sys.exit(main())
