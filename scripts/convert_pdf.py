#!/usr/bin/env python3
"""One-off converter: 1500_english_words_US_RU.pdf -> data/core-1500.json.

The PDF is a frequency list laid out as two column groups per page (left
group: words #1-750, right group: #751-1500), each a (No, English, Перевод)
table. Rows can be two text lines tall: 4-digit numbers and long English
words wrap inside their narrow cells while the translation sits vertically
centered, so line-based text extraction breaks. Instead, every table row is
backed by a full-width zebra rectangle (white rows included) — those rects
give exact row bands, and tokens are assigned to (band, half, column) by
coordinates.

Usage (from repo root):
    python3 -m venv .venv && .venv/bin/pip install pdfplumber
    .venv/bin/python scripts/convert_pdf.py
"""

import json
import re
import sys
from pathlib import Path

import pdfplumber

REPO_ROOT = Path(__file__).resolve().parent.parent
PDF_PATH = REPO_ROOT / "1500_english_words_US_RU.pdf"
OUT_PATH = REPO_ROOT / "data" / "core-1500.json"

EXPECTED_COUNT = 1500
# Column x-boundaries within each half, measured from the table's left edge
# (left half starts at ~45.6, right half at ~297.6; the halves are shifted
# copies 252pt apart). Values chosen between observed column x-ranges.
HALF_OFFSETS = (0.0, 252.0)
NUMBER_END = 70.0       # digits end (right-aligned) before this
ENGLISH_END = 141.0     # english column ends / translation starts here
MIN_ROW_HEIGHT = 10.0   # rows are ~14.4pt (single-line) or ~24.4pt (wrapped);
                        # the header band is filtered out later ('№' is not a digit)
SAME_LINE_TOLERANCE = 2.5
CYRILLIC_RE = re.compile(r"[а-яА-ЯёЁ]")
ENGLISH_RE = re.compile(r"^[a-zA-Z][a-zA-Z'’\- ]*$")


def row_bands(page):
    """Full-width zebra rects -> sorted list of (top, bottom) row bands."""
    bands = [
        (r["top"], r["bottom"])
        for r in page.rects
        if r["bottom"] - r["top"] >= MIN_ROW_HEIGHT and r["x1"] - r["x0"] > page.width * 0.7
    ]
    return sorted(set(bands))


def join_fragments(fragments):
    """Join cell fragments: space within one text line, nothing across a wrap."""
    fragments = sorted(fragments, key=lambda w: (w["top"], w["x0"]))
    result = ""
    previous_top = None
    for fragment in fragments:
        if not result:
            result = fragment["text"]
        elif previous_top is not None and abs(fragment["top"] - previous_top) <= SAME_LINE_TOLERANCE:
            result += " " + fragment["text"]
        else:
            result += fragment["text"]  # wrapped continuation of the same token
        previous_top = fragment["top"]
    return result


def parse_row(cell_words, page_number, half_index):
    """One (band, half) cell set -> (id, english, raw_translation) or None."""
    if not cell_words:
        return None
    offset = HALF_OFFSETS[half_index]
    numbers, english, translation = [], [], []
    for word in cell_words:
        x = word["x0"] - offset
        if x < NUMBER_END:
            numbers.append(word)
        elif x < ENGLISH_END:
            english.append(word)
        else:
            translation.append(word)

    number_text = join_fragments(numbers)
    if not number_text.isdigit():
        return None  # header row or stray non-data content
    english_text = join_fragments(english)
    translation_text = " ".join(
        w["text"] for w in sorted(translation, key=lambda w: (w["top"], w["x0"]))
    )
    where = f"page {page_number}, half {half_index}, row #{number_text}"
    if not english_text or not ENGLISH_RE.match(english_text):
        raise SystemExit(f"{where}: unexpected english cell {english_text!r}")
    if not CYRILLIC_RE.search(translation_text):
        raise SystemExit(f"{where}: unexpected translation cell {translation_text!r}")
    return int(number_text), english_text, translation_text


def extract_rows(pdf_path):
    rows = []
    with pdfplumber.open(pdf_path) as pdf:
        for page_number, page in enumerate(pdf.pages, start=1):
            words = page.extract_words()
            midline = page.width / 2
            for top, bottom in row_bands(page):
                in_band = [
                    w for w in words if top - 1 <= (w["top"] + w["bottom"]) / 2 <= bottom + 1
                ]
                for half_index, half_words in enumerate(
                    (
                        [w for w in in_band if w["x1"] <= midline],
                        [w for w in in_band if w["x0"] > midline],
                    )
                ):
                    row = parse_row(half_words, page_number, half_index)
                    if row is not None:
                        rows.append(row)
    return rows


def parse_translation(raw):
    """Split a raw translation cell into discrete meanings + optional note."""
    notes = [n.strip() for n in re.findall(r"\(([^)]*)\)", raw) if n.strip()]
    stripped = re.sub(r"\([^)]*\)", " ", raw)
    parts = re.split(r"[;,]", stripped)
    translations = [re.sub(r"\s+", " ", p).strip(" .") for p in parts]
    translations = [p for p in translations if p]
    note = "; ".join(notes) if notes else None
    return translations, note


def build_batch(rows):
    by_id = {}
    for word_id, english, raw_translation in rows:
        if word_id in by_id:
            raise SystemExit(f"duplicate id {word_id}: {english!r} vs {by_id[word_id]['word']!r}")
        translations, note = parse_translation(raw_translation)
        if not translations:
            raise SystemExit(f"word #{word_id} ({english}) has empty translations: {raw_translation!r}")
        entry = {"id": word_id, "word": english, "translations": translations}
        if note:
            entry["note"] = note
        by_id[word_id] = entry

    missing = sorted(set(range(1, EXPECTED_COUNT + 1)) - set(by_id))
    extra = sorted(set(by_id) - set(range(1, EXPECTED_COUNT + 1)))
    if missing or extra:
        raise SystemExit(f"id coverage broken: missing={missing[:20]} extra={extra[:20]}")

    return {
        "schemaVersion": 1,
        "batchId": "core-1500",
        "title": "1500 самых употребляемых английских слов",
        "category": None,
        "words": [by_id[i] for i in range(1, EXPECTED_COUNT + 1)],
    }


def spot_check(batch):
    words = {entry["word"]: entry for entry in batch["words"]}
    checks = [
        ("the", lambda e: "артикль" in e["translations"] and e["id"] == 1),
        ("ring", lambda e: {"кольцо", "звонить"} <= set(e["translations"])),
        ("shop", lambda e: "магазин" in e["translations"]),
        ("store", lambda e: "магазин" in e["translations"]),
        ("uncomfortable", lambda e: bool(e["translations"])),
    ]
    for word, check in checks:
        if word not in words or not check(words[word]):
            raise SystemExit(f"spot check failed for {word!r}: {words.get(word)}")


def main():
    if not PDF_PATH.exists():
        raise SystemExit(f"PDF not found: {PDF_PATH}")
    rows = extract_rows(PDF_PATH)
    batch = build_batch(rows)
    spot_check(batch)
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(batch, f, ensure_ascii=False, indent=1)
        f.write("\n")
    noted = sum(1 for e in batch["words"] if "note" in e)
    multi = sum(1 for e in batch["words"] if len(e["translations"]) > 1)
    print(f"OK: {len(batch['words'])} words -> {OUT_PATH.relative_to(REPO_ROOT)}")
    print(f"    with note: {noted}, multi-translation: {multi}")


if __name__ == "__main__":
    sys.exit(main())
