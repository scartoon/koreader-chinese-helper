#!/usr/bin/env python3
"""Pull the EPUBs from a USB-connected Android device and extract their Chinese
text, for measuring dictionary coverage on real reading material.

    python3 tools/fetch_books.py                      # /sdcard/Books -> build/books, build/corpus
    python3 tools/fetch_books.py --device-dir /sdcard/Books --min-han 20000
    python3 tools/fetch_books.py --local linggao BOOK.epub ...   # files on this computer
    python3 tools/fetch_books.py --local linggao books.zip       # ... or the EPUBs inside a zip

Everything goes into build/ (git-ignored): the books are the reader's own and
are never committed.

  build/books/<n>.epub      the pulled files (re-pulled only when the size changed)
  build/corpus/<n>.txt      one paragraph per line, in reading order (spine)
  build/corpus/index.tsv    n, Han characters, share of Han among non-space
                            characters, kept (1/0), device file name

A book is kept when it has at least --min-han Han characters and Han is at
least --min-share of its non-space characters: Chinese books, not English
ones quoting a few characters. Formats other than EPUB are listed and skipped.

--local NAME FILE...: no device; the EPUBs given (or every EPUB inside a
given .zip) are copied to build/books/NAME-<k>.epub and extracted to
build/corpus/NAME-<k>.txt, with the same filters. Their rows replace any
earlier NAME-* rows in build/corpus/index.tsv; the device's rows are kept.
tools/measure_fallback.py --book NAME then measures those files alone.
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


def extract(local, k, min_han, min_share, name):
    """Write build/corpus/<k>.txt for a kept book; its index row."""
    try:
        paras = list(paragraphs(local))
    except zipfile.BadZipFile:
        return (k, 0, 0.0, 0, name)
    han = sum(len(HAN_RE.findall(p)) for p in paras)
    nonspace = sum(len(p.replace(" ", "")) for p in paras) or 1
    share = han / nonspace
    keep = han >= min_han and share >= min_share
    if keep:
        with open(os.path.join(CORPUS, f"{k}.txt"), "w", encoding="utf-8") as f:
            f.write("\n".join(paras) + "\n")
    return (k, han, share, int(keep), name)


def zip_member_name(info):
    """A zip member's file name, also when the archiver wrote UTF-8 names
    without setting the UTF-8 flag (Google Drive downloads do)."""
    if info.flag_bits & 0x800:
        return info.filename
    try:
        return info.filename.encode("cp437").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return info.filename


def local_books(paths):
    """[(display name, bytes)] of the EPUBs given, opening any .zip given."""
    out = []
    for path in paths:
        if path.lower().endswith(".zip"):
            with zipfile.ZipFile(path) as z:
                for info in sorted(z.infolist(), key=zip_member_name):
                    name = zip_member_name(info)
                    if name.lower().endswith(".epub"):
                        out.append((f"{os.path.basename(path)}:{posixpath.basename(name)}", z.read(info)))
        elif path.lower().endswith(".epub"):
            with open(path, "rb") as f:
                out.append((os.path.basename(path), f.read()))
        else:
            print(f"skipped (not EPUB or zip): {path}")
    return out


def write_index(rows, others=(), keep_rows=lambda n: False):
    """index.tsv: these rows, plus the existing rows keep_rows() accepts."""
    path = os.path.join(CORPUS, "index.tsv")
    kept_lines = []
    if os.path.exists(path):
        for line in open(path, encoding="utf-8").read().splitlines()[1:]:
            if keep_rows(line.split("\t", 1)[0]):
                kept_lines.append(line)
    with open(path, "w", encoding="utf-8") as f:
        f.write("n\than\tshare\tkept\tfile\n")
        for line in kept_lines:
            f.write(line + "\n")
        for k, han, share, keep, name in rows:
            f.write(f"{k}\t{han}\t{share:.3f}\t{keep}\t{name}\n")
        for name in others:
            f.write(f"-\t-\t-\tskipped (format)\t{name}\n")


def main_local(args):
    prefix = args.local[0]
    if not re.fullmatch(r"[a-z][a-z0-9_]*", prefix):
        sys.exit("--local NAME: lower-case letters, digits and _ (it prefixes the file names)")
    books = local_books(args.local[1:])
    if not books:
        sys.exit("no EPUBs found in the files given")
    rows = []
    for k, (name, data) in enumerate(books, 1):
        key = f"{prefix}-{k}"
        local = os.path.join(BOOKS, key + ".epub")
        if not (os.path.exists(local) and os.path.getsize(local) == len(data)):
            with open(local, "wb") as f:
                f.write(data)
        rows.append(extract(local, key, args.min_han, args.min_share, name))
    write_index(rows, keep_rows=lambda n: not n.startswith(prefix + "-"))
    kept = [r for r in rows if r[3]]
    for k, han, share, keep, name in rows:
        print(f"  {k}: {han:,} Han characters, {'kept' if keep else 'not kept'}")
    print(f"kept {len(kept)} Chinese books, {sum(r[1] for r in kept):,} Han characters -> build/corpus/{prefix}-*.txt")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--device-dir", default="/sdcard/Books")
    ap.add_argument("--local", nargs="+", metavar=("NAME", "FILE"),
                    help="no device: copy these EPUBs (or the EPUBs inside these zips) as NAME-<k>")
    ap.add_argument("--min-han", type=int, default=20000)
    ap.add_argument("--min-share", type=float, default=0.5)
    args = ap.parse_args()
    os.makedirs(BOOKS, exist_ok=True)
    os.makedirs(CORPUS, exist_ok=True)
    if args.local:
        if len(args.local) < 2:
            ap.error("--local NAME FILE...")
        return main_local(args)

    files = device_listing(args.device_dir)
    epubs = sorted((n, s) for n, s in files if n.lower().endswith(".epub"))
    others = sorted(n for n, _ in files if n.lower().endswith((".mobi", ".azw3", ".azw", ".fb2", ".txt", ".pdf")))
    print(f"{args.device_dir}: {len(epubs)} EPUBs; skipped (not EPUB): {len(others)}")
    rows = []
    for k, (name, size) in enumerate(epubs, 1):
        local = os.path.join(BOOKS, f"{k:03d}.epub")
        if not (os.path.exists(local) and os.path.getsize(local) == size):
            adb("pull", f"{args.device_dir}/{name}", local)
        rows.append(extract(local, f"{k:03d}", args.min_han, args.min_share, name))
    # Rows for books added with --local stay.
    write_index(rows, others, keep_rows=lambda n: "-" in n and n != "-")
    kept = [r for r in rows if r[3]]
    print(f"kept {len(kept)} Chinese books, {sum(r[1] for r in kept):,} Han characters -> build/corpus/")


if __name__ == "__main__":
    sys.exit(main())
