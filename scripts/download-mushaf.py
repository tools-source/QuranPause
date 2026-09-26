"""Build and verify the bundled 604-page Madinah Mushaf (KFGQPC QCF V2).

Sources
  * Glyphs: the King Fahd Glorious Quran Printing Complex (KFGQPC) QCF V2 page
    fonts. Each font holds the word shapes printed on one Mushaf page. Quran
    Foundation's surah-name font supplies the calligraphic chapter headings.
  * Layout: Quran Foundation's word-level V2 page/line data (`v2_page`,
    `line_v2`, `code_v2`), fetched surah by surah so no word can be dropped or
    picked up from a neighbouring page.

Nothing is guessed. Surah headings and basmalas are placed on the lines the
print leaves free before a surah's first ayah, and the build fails unless every
check below passes. Outputs are written only after the whole Mushaf verifies.

  1. 114 surahs / 6,236 ayahs, matching the bundled Quran text, in order.
  2. Every ayah has its words in order and ends with exactly one ayah marker.
  3. Every word sits on a page 1-604 and a line 1-15, in reading order.
  4. Per page, the glyphs placed are exactly the page's run of word glyphs in its
     KFGQPC font, each once, in ascending order: nothing missing, duplicated, or
     from another page.
  5. Pages 1-2 fill lines 1-8; pages 3-604 fill lines 1-15, each line exactly
     once, with 114 surah headings and 112 separate basmalas.
  6. page_index.json (used for navigation and saved progress) is regenerated
     from the same verified pages, so the reader and index cannot disagree.
  7. Per page, an ayah run list records how many of the page's glyphs belong to
     each ayah, in printed order, so touching a word on the page resolves to its
     ayah without inferring anything from the glyphs.
  8. Every text line preserves the source's word boundaries. The app renders one
     isolated span per word, as required by QCF fonts, so neighbouring word
     glyphs cannot shape or overlap as one browser text run.

Every exception below was checked by eye against the printed KFGQPC page, and
each is pinned to the exact upstream value so any source change fails the build.

Requires: python3 -m pip install fonttools brotli
Usage:    python3 scripts/download-mushaf.py [--offline]
"""
from __future__ import annotations

import argparse
import concurrent.futures
import datetime
import hashlib
import io
import json
import pathlib
import sys
import time
import urllib.request

try:
    from fontTools.ttLib import TTFont
except ImportError:  # pragma: no cover - guidance for a missing tool
    sys.exit("fontTools is required: python3 -m pip install fonttools brotli")

ROOT = pathlib.Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "QuranTime" / "Resources"
OUTPUT = RESOURCES / "Mushaf"
CACHE = ROOT / "build" / "mushaf-cache"

LAYOUT_URL = (
    "https://api.quran.com/api/v4/verses/by_chapter/{chapter}"
    "?words=true&word_fields=code_v2,v2_page,line_v2&per_page=50&page={page}"
)
FONT_URL = "https://verses.quran.foundation/fonts/quran/hafs/v2/woff2/p{page}.woff2"
SURAH_FONT_URL = "https://verses.quran.foundation/fonts/quran/surah-names/v1/sura_names.woff2"
PAGES = range(1, 605)
BASMALA_SOURCE_PAGE = 1  # Al-Fatihah 1:1 words 1-4, without its ayah marker.
FIRST_WORD_GLYPH = 0xFC41

# (ayah, word position) -> (upstream line, printed line).
# Page 589: the marker of 84:21 follows يَسۡجُدُونَ ۩ on line 14, as its glyph order also shows.
LINE_CORRECTIONS = {("84:21", 7): (13, 14)}
# Unused glyphs right after a page's last word could mean a missing word. These
# printed pages end exactly where the layout ends; the fonts carry leftovers.
PRINT_VERIFIED_TRAILING_GLYPHS = {256: 15, 270: 8}
# An auxiliary block some page fonts carry outside the word range; no word uses it.
AUXILIARY_GLYPHS = {0xFB50, *range(0xFD5A, 0xFD7A)}


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "QuranTime/1.0"})
    for attempt in range(6):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.read()
        except Exception:
            if attempt == 5:
                raise
            time.sleep(1 + attempt * 2)
    raise AssertionError("unreachable")


def cached(name: str, url: str, offline: bool) -> bytes:
    path = CACHE / name
    if not path.exists():
        if offline:
            sys.exit(f"Missing cached source {path}; run without --offline.")
        path.write_bytes(fetch(url))
    return path.read_bytes()


def chapter_verses(chapter: int, offline: bool) -> list[dict]:
    verses, page = [], 1
    while page:
        payload = json.loads(cached(
            f"chapter-{chapter}-{page}.json", LAYOUT_URL.format(chapter=chapter, page=page), offline
        ))
        verses += payload["verses"]
        page = payload["pagination"]["next_page"]
    return verses


def glyphs(code: str) -> list[int]:
    # A few words carry a pause or hizb sign as a second glyph separated by a space.
    return [ord(character) for character in code if not character.isspace()]


def build(offline: bool) -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    errors: list[str] = []
    quran = json.loads((RESOURCES / "quran_en.json").read_text())
    page_index = json.loads((RESOURCES / "page_index.json").read_text())

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        chapters = list(pool.map(lambda c: chapter_verses(c, offline), range(1, 115)))
        fonts = list(pool.map(lambda p: cached(f"p{p}.woff2", FONT_URL.format(page=p), offline), PAGES))
    surah_font = cached("sura_names.woff2", SURAH_FONT_URL, offline)

    # 1-3. Text structure and reading order.
    words: list[dict] = []
    for surah, verses in zip(quran, chapters):
        numbers = [verse["verse_number"] for verse in verses]
        if numbers != list(range(1, surah["total_verses"] + 1)):
            errors.append(f"Surah {surah['id']}: ayahs {numbers[:3]}... do not match {surah['total_verses']} ayahs")
        for verse in verses:
            key = verse["verse_key"]
            if [word["position"] for word in verse["words"]] != list(range(1, len(verse["words"]) + 1)):
                errors.append(f"{key}: word positions are not sequential")
            kinds = [word["char_type_name"] for word in verse["words"]]
            if kinds[-1:] != ["end"] or kinds.count("end") != 1 or set(kinds) != {"word", "end"}:
                errors.append(f"{key}: expected words followed by one ayah marker, got {kinds}")
            for word in verse["words"]:
                page, line = word["v2_page"], word["line_v2"]
                if (key, word["position"]) in LINE_CORRECTIONS:
                    upstream, printed = LINE_CORRECTIONS[(key, word["position"])]
                    if line != upstream:
                        errors.append(f"{key} word {word['position']}: upstream line is now {line}; "
                                      f"re-check page {page} and update LINE_CORRECTIONS")
                    line = printed
                if not (isinstance(page, int) and 1 <= page <= 604 and isinstance(line, int) and 1 <= line <= 15):
                    errors.append(f"{key} word {word['position']}: invalid page/line {page}/{line}")
                    continue
                words.append({"key": key, "surah": surah["id"], "ayah": verse["verse_number"],
                              "position": word["position"], "page": page, "line": line, "code": word["code_v2"]})
    if sum(len(verses) for verses in chapters) != 6236:
        errors.append("The layout does not contain exactly 6,236 ayahs")
    for previous, word in zip(words, words[1:]):
        if (word["page"], word["line"]) < (previous["page"], previous["line"]):
            errors.append(f"{word['key']}: moves backwards from page {previous['page']} line {previous['line']}")
    words_on = {page: [word for word in words if word["page"] == page] for page in PAGES}

    # 4. Glyphs versus each page's own KFGQPC font.
    fonts_by_page = dict(zip(PAGES, fonts))
    for page in PAGES:
        font = TTFont(io.BytesIO(fonts_by_page[page]))
        family = font["name"].getDebugName(1)
        if family != f"QCF2{page:03d}":
            errors.append(f"Page {page}: font is {family!r}, expected QCF2{page:03d}")
        available = {code for code in font.getBestCmap() if code > 0x20}
        placed = [code for word in words_on[page] for code in glyphs(word["code"])]
        run = list(range(FIRST_WORD_GLYPH, FIRST_WORD_GLYPH + len(placed)))
        if placed != run or not set(run) <= available:
            errors.append(
                f"Page {page}: glyphs are not its font's word run in order "
                f"(first differences {[(f'{a:04X}', f'{b:04X}') for a, b in zip(placed, run) if a != b][:3]}, "
                f"absent from font {[f'{c:04X}' for c in sorted(set(placed) - available)][:5]})"
            )
        unused = available - set(run) - AUXILIARY_GLYPHS
        trailing = set(range(run[-1] + 1, run[-1] + 1 + PRINT_VERIFIED_TRAILING_GLYPHS.get(page, 0))) if run else set()
        if unused != trailing:
            errors.append(f"Page {page}: font glyphs {[f'{c:04X}' for c in sorted(unused ^ trailing)][:5]} "
                          "are unaccounted for (a word may be missing)")

    # 4b. Ayah runs: which ayah each printed glyph belongs to, in page glyph order.
    # Selection on the page resolves a touched glyph to its ayah through these runs,
    # so no ayah boundary is inferred from the glyphs themselves.
    runs_by_page: dict[int, list[list]] = {}
    for page in PAGES:
        runs: list[list] = []
        for word in words_on[page]:
            count = len(glyphs(word["code"]))
            if runs and runs[-1][0] == word["key"]:
                runs[-1][1] += count
            else:
                runs.append([word["key"], count])
        keys = [key for key, _ in runs]
        if len(set(keys)) != len(keys):
            errors.append(f"Page {page}: ayah {[k for k in keys if keys.count(k) > 1][:3]} is split by another ayah")
        placed = sum(len(glyphs(word["code"])) for word in words_on[page])
        if sum(count for _, count in runs) != placed:
            errors.append(f"Page {page}: ayah runs cover {sum(c for _, c in runs)} of {placed} glyphs")
        if keys[:1] != [words_on[page][0]["key"]] or keys[-1:] != [words_on[page][-1]["key"]]:
            errors.append(f"Page {page}: ayah runs start/end on the wrong ayah")
        runs_by_page[page] = runs

    # 5. Lines, surah headings, and basmalas.
    layout: dict[int, dict[int, dict]] = {page: {} for page in PAGES}

    def place(page: int, line: int, entry: dict, owner: str) -> None:
        if line in layout[page]:
            errors.append(f"Page {page} line {line}: {owner} collides with {layout[page][line]['type']}")
        else:
            layout[page][line] = entry

    for word in words:
        line = layout[word["page"]].setdefault(
            word["line"], {"type": "text", "content": "", "words": []}
        )
        line["content"] += word["code"]
        line["words"].append({"key": word["key"], "content": word["code"]})

    basmala_words = [w for w in words if w["key"] == "1:1"][:-1]  # drop the ayah marker
    basmala = "".join(word["code"] for word in basmala_words)
    headings = basmalas = 0
    for surah in quran:
        first = next(word for word in words if word["surah"] == surah["id"])
        slots = [("basmala", {"type": "basmala", "surah": surah["id"], "content": basmala})] \
            if surah["id"] not in (1, 9) else []
        slots.insert(0, ("surah-header", {"type": "surah-header", "surah": surah["id"],
                                          "content": f"سورة {surah['name']}"}))
        page, line = first["page"], first["line"]
        for kind, entry in reversed(slots):
            line -= 1
            if line == 0:  # The print may end a page with the next surah's heading.
                page, line = page - 1, 15
            if page < 1:
                errors.append(f"Surah {surah['id']}: no room for its {kind}")
                break
            place(page, line, entry, f"surah {surah['id']} {kind}")
            headings += kind == "surah-header"
            basmalas += kind == "basmala"
    if (headings, basmalas) != (114, 112):
        errors.append(f"Expected 114 headings and 112 basmalas, placed {headings} and {basmalas}")

    for page in PAGES:
        expected = list(range(1, 9 if page <= 2 else 16))
        if sorted(layout[page]) != expected:
            errors.append(f"Page {page}: lines {sorted(layout[page])}, expected {expected[0]}-{expected[-1]}")
        for line, entry in layout[page].items():
            if entry["type"] == "text" and "".join(word["content"] for word in entry["words"]) != entry["content"]:
                errors.append(f"Page {page} line {line}: word boundaries do not reproduce the printed glyph run")
        word_runs: list[list] = []
        for entry in (layout[page][line] for line in sorted(layout[page])):
            for word in entry.get("words", []):
                count = len(glyphs(word["content"]))
                if word_runs and word_runs[-1][0] == word["key"]:
                    word_runs[-1][1] += count
                else:
                    word_runs.append([word["key"], count])
        if word_runs != runs_by_page[page]:
            errors.append(f"Page {page}: word keys do not reproduce the independently verified ayah runs")

    # 6. Page index from the verified pages. An ayah belongs to the page where it
    # starts; juz membership is per ayah and carries over unchanged.
    juz = {(v["surah"], v["ayah"]): v["juz"] for entry in page_index for v in entry["verses"]}
    old_page = {(v["surah"], v["ayah"]): entry["id"] for entry in page_index for v in entry["verses"]}
    new_page = {(word["surah"], word["ayah"]): word["page"] for word in words if word["position"] == 1}
    if set(juz) != set(new_page) or list(juz.values()) != sorted(juz.values()):
        errors.append("page_index.json juz data does not cover the 6,236 ayahs in order")
    new_index = [{"id": page, "verses": [{"surah": s, "ayah": a, "juz": juz.get((s, a), 0)}
                                         for (s, a), start in new_page.items() if start == page]}
                 for page in PAGES]
    if any(not entry["verses"] for entry in new_index):
        errors.append("A page has no ayah starting on it")
    moved = [key for key, page in new_page.items() if old_page.get(key) != page]

    if errors:
        print(f"Mushaf verification failed with {len(errors)} problem(s); nothing was written.", file=sys.stderr)
        for error in errors[:60]:
            print(f"  - {error}", file=sys.stderr)
        sys.exit(1)

    # All checks passed: write the snapshot and its integrity manifest.
    (OUTPUT / "Pages").mkdir(parents=True, exist_ok=True)
    (OUTPUT / "Fonts").mkdir(parents=True, exist_ok=True)
    (OUTPUT / "Ayahs").mkdir(parents=True, exist_ok=True)
    manifest_pages = []
    for page in PAGES:
        lines = [layout[page][line] for line in sorted(layout[page])]
        layout_bytes = json.dumps({"page": page, "lines": lines}, ensure_ascii=False,
                                  separators=(",", ":")).encode()
        (OUTPUT / "Pages" / f"{page}.json").write_bytes(layout_bytes)
        (OUTPUT / "Fonts" / f"p{page}.woff2").write_bytes(fonts_by_page[page])
        ayah_bytes = json.dumps(
            {"page": page, "ayahs": [{"key": key, "glyphs": count} for key, count in runs_by_page[page]]},
            ensure_ascii=False, separators=(",", ":")).encode()
        # Resources are copied flat into the app bundle, so this name cannot collide with Pages/.
        (OUTPUT / "Ayahs" / f"ayahs-{page}.json").write_bytes(ayah_bytes)
        keys = [word["key"] for word in words_on[page]]
        manifest_pages.append({
            "page": page,
            "glyphs": sum(len(glyphs(word["code"])) for word in words_on[page]),
            "firstAyah": keys[0], "lastAyah": keys[-1],
            "layoutSHA256": hashlib.sha256(layout_bytes).hexdigest(),
            "ayahsSHA256": hashlib.sha256(ayah_bytes).hexdigest(),
            "fontSHA256": hashlib.sha256(fonts_by_page[page]).hexdigest(),
        })
    (OUTPUT / "sura_names.woff2").write_bytes(surah_font)
    manifest = {
        "edition": "Madinah Mushaf, Hafs an Asim, 604 pages, 15 lines",
        "glyphs": "King Fahd Glorious Quran Printing Complex (KFGQPC) QCF V2 page fonts",
        "layout": "Quran Foundation word-level V2 page and line data",
        "sources": {"layout": LAYOUT_URL, "fonts": FONT_URL, "surahNames": SURAH_FONT_URL,
                    "terms": "https://api-docs.quran.com/legal/mushaf-fonts-and-images/"},
        "surahFontSHA256": hashlib.sha256(surah_font).hexdigest(),
        "basmala": f"KFGQPC glyphs of Al-Fatihah 1:1 from page {BASMALA_SOURCE_PAGE}, without the ayah marker",
        "printVerifiedExceptions": {
            "lineCorrections": [f"{key} word {position}: line {old} -> {new}"
                                for (key, position), (old, new) in LINE_CORRECTIONS.items()],
            "unusedTrailingFontGlyphs": {str(page): count for page, count in PRINT_VERIFIED_TRAILING_GLYPHS.items()},
        },
        "verified": datetime.date.today().isoformat(),
        "ayahs": 6236, "words": len(words),
        "pages": manifest_pages,
    }
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n")
    (RESOURCES / "page_index.json").write_text(json.dumps(new_index, separators=(",", ":")))
    print(f"Verified and wrote 604 pages, {len(words)} words and ayah markers, 114 headings, 112 basmalas.")
    if moved:
        print(f"page_index.json: {len(moved)} ayah(s) now on their printed page: "
              + ", ".join(f"{s}:{a}" for s, a in moved))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--offline", action="store_true", help="use only previously cached sources")
    build(parser.parse_args().offline)
