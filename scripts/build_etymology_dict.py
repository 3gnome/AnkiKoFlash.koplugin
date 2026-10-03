#!/usr/bin/env python3
"""Build an etymology-only StarDict dictionary from the Wiktionary English StarDict.

Inputs (in --input, default ``dictionaries/``)::

    en-en.ifo      StarDict metadata
    en-en.idx      word index (32-bit big-endian offsets)
    en-en.dict.dz  idzip-compressed definitions

Outputs (in --output, default ``dictionaries/build/``)::

    etymology.ifo
    etymology.idx
    etymology.dict   plain-text etymology sections only

Entries without an Etymology section are dropped.  The resulting dictionary is
self-contained and reads cleanly as the ``Etymology`` card field.

Requires only the Python standard library (``gzip``, ``struct``, ``html.parser``).
"""
import argparse
import gzip
import os
import re
import struct
from datetime import date
from html.parser import HTMLParser

_HEADINGS = {"h1", "h2", "h3", "h4", "h5", "h6"}


class _EtymologyExtractor(HTMLParser):
    """Collect the text of every ``Etymology`` section in one definition."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []            # open tag names (lowercase)
        self.in_heading = False
        self.heading_text = []
        self.capturing = False
        self.capture_until = 0
        self.buf = []
        self.sections = []

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        if tag in _HEADINGS:
            self.in_heading = True
            self.heading_text = []
        elif tag == "br" and self.capturing:
            self.buf.append(" ")
        self.stack.append(tag)

    def handle_startendtag(self, tag, attrs):
        tag = tag.lower()
        if tag == "br" and self.capturing:
            self.buf.append(" ")

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag in _HEADINGS:
            self.in_heading = False
            text = "".join(self.heading_text).strip()
            if re.match(r"(?i)^etymology\b", text):
                self.capturing = True
                # Stop capturing when the section wrapping this heading closes.
                self.capture_until = len(self.stack) - 1
            self.heading_text = []
        if self.stack:
            self.stack.pop()
        if self.capturing and len(self.stack) < self.capture_until:
            self.capturing = False
            self.sections.append(re.sub(r"\s+", " ", "".join(self.buf)).strip())
            self.buf = []

    def handle_data(self, data):
        if self.in_heading:
            self.heading_text.append(data)
        elif self.capturing:
            self.buf.append(data)


def extract_etymology(definition: str) -> str:
    """Return plain-text etymology (multiple sections joined by blank lines)."""
    parser = _EtymologyExtractor()
    try:
        parser.feed(definition)
        parser.close()
    except Exception:
        pass
    parts = [p for p in parser.sections if p]
    return "\n\n".join(parts)


def read_ifo(path):
    fields = {}
    with open(path, "rb") as f:
        for raw in f.read().decode("utf-8", "replace").splitlines():
            if "=" in raw:
                key, _, value = raw.partition("=")
                fields[key.strip()] = value.strip()
    return fields


def iter_idx(path):
    """Yield (word, offset, size) in index order (offset-contiguous)."""
    with open(path, "rb") as f:
        data = f.read()
    pos = 0
    n = len(data)
    while pos < n:
        nul = data.find(b"\0", pos)
        if nul < 0:
            break
        word = data[pos:nul].decode("utf-8", "replace")
        pos = nul + 1
        if pos + 8 > n:
            break
        offset, size = struct.unpack_from(">II", data, pos)
        pos += 8
        yield word, offset, size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default=None)
    ap.add_argument("--output", default=None)
    ap.add_argument("--bookname", default="Etymology (Wiktionary)")
    args = ap.parse_args()

    root = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.dirname(root)
    input_dir = args.input or os.path.join(repo, "dictionaries")
    output_dir = args.output or os.path.join(repo, "dictionaries", "build")

    ifo_path = os.path.join(input_dir, "en-en.ifo")
    idx_path = os.path.join(input_dir, "en-en.idx")
    dict_path = os.path.join(input_dir, "en-en.dict.dz")

    os.makedirs(output_dir, exist_ok=True)

    info = read_ifo(ifo_path)
    total_words = int(info.get("wordcount", 0))

    out_idx = os.path.join(output_dir, "etymology.idx")
    out_dict = os.path.join(output_dir, "etymology.dict")
    out_ifo = os.path.join(output_dir, "etymology.ifo")

    kept = 0
    out_offset = 0
    idx_size = 0
    skipped = 0

    with gzip.open(dict_path, "rb") as dz, \
            open(out_idx, "wb") as idxf, \
            open(out_dict, "wb") as dictf:
        for word, _offset, size in iter_idx(idx_path):
            chunk = dz.read(size)
            if len(chunk) != size:
                skipped += 1
                continue
            definition = chunk.decode("utf-8", "replace")
            etymology = extract_etymology(definition)
            if not etymology:
                continue
            payload = etymology.encode("utf-8")
            idxf.write(word.encode("utf-8") + b"\0")
            idxf.write(struct.pack(">II", out_offset, len(payload)))
            idx_size += len(word.encode("utf-8")) + 1 + 8
            dictf.write(payload)
            out_offset += len(payload)
            kept += 1

    if kept == 0:
        raise SystemExit("No etymology entries extracted; check input files.")

    with open(out_ifo, "w", encoding="utf-8") as f:
        f.write(
            "StarDict's dict ifo file\n"
            "version=3.0.0\n"
            f"bookname={args.bookname}\n"
            f"wordcount={kept}\n"
            f"idxfilesize={idx_size}\n"
            "sametypesequence=m\n"
            "author=Wiktionary (xxyzz snapshot)\n"
            "website=https://github.com/xxyzz/wiktionary_stardict\n"
            f"description=English etymology extracted from Wiktionary snapshot "
            f"{info.get('description', '')}\n"
            f"date={date.today().isoformat()}\n"
            "lang=en-en\n"
        )

    print(
        f"Kept {kept} etymology entries of {total_words} words "
        f"({skipped} truncated reads skipped)."
    )
    print(f"Output: {out_ifo}, {out_idx}, {out_dict}")


if __name__ == "__main__":
    main()
