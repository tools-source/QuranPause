"""Build and verify the bundled catalogue of full-surah recitations.

Source: Quran Foundation's recitation catalogue (api.quran.com) and its audio CDN,
download.quranicaudio.com. The app streams these files; only their addresses are bundled.

A reciter is included only if every check passes:
  1. Exactly one recording for each of the 114 surahs (empty catalogue rows are ignored).
  2. All 114 files live in one folder on download.quranicaudio.com, so no file is
     borrowed from another reciter or collection.
  3. Every file answers over HTTPS as audio/mpeg.
  4. Every file's real duration, read from its MP3 header, is in proportion to its
     surah: within 0.5x-2x of that reciter's median seconds per word. A truncated
     file or one attached to the wrong surah falls far outside this range.
     (The catalogue's own file sizes are unreliable and are not used.)

A reciter that fails is a build error unless it is listed in EXCLUDED with the reason,
so nothing is dropped silently. Output is written only when all checks pass.

Usage: python3 scripts/download-recitations.py
"""
from __future__ import annotations

import concurrent.futures
import datetime
import json
import pathlib
import sys
import time
import urllib.error
import urllib.request
from urllib.parse import urlparse

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "QuranTime" / "Resources" / "recitations.json"
API = "https://api.quran.com/api/v4"
AUDIO_HOST = "download.quranicaudio.com"

EXCLUDED = {
    8: "Every catalogued file (siddiq_al-minshawi/mujawwad) returns HTTP 404.",
    11: "Catalogue lists 128 files and surah 1 is in another reciter's folder (abdul_muhsin_alqasim).",
}
QURAN = json.loads((ROOT / "QuranTime" / "Resources" / "quran_en.json").read_text())
WORDS = {surah["id"]: sum(len(verse["text"].split()) for verse in surah["verses"]) for surah in QURAN}
MPEG1_KBPS = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
MPEG2_KBPS = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]
SAMPLE_RATES = {3: [44100, 48000, 32000], 2: [22050, 24000, 16000], 0: [11025, 12000, 8000]}


def request(url: str, method: str = "GET"):
    req = urllib.request.Request(url, method=method, headers={"User-Agent": "QuranTime/1.0"})
    for attempt in range(6):
        try:
            return urllib.request.urlopen(req, timeout=60)
        except urllib.error.HTTPError as error:
            if error.code < 500 or attempt == 5:
                raise
            time.sleep(1 + attempt * 2)
        except Exception:
            if attempt == 5:
                raise
            time.sleep(1 + attempt * 2)


def get_json(url: str) -> dict:
    with request(url) as response:
        return json.load(response)


def read_range(url: str, start: int, length: int) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "QuranTime/1.0", "Range": f"bytes={start}-{start + length - 1}"})
    with urllib.request.urlopen(req, timeout=60) as response:
        return response.read()


def mp3_seconds(url: str, size: int) -> float:
    """Duration from the first MPEG Layer III frame: its Xing/Info frame count, else constant bitrate."""
    head = read_range(url, 0, 10)
    offset = 10 + ((head[6] << 21) | (head[7] << 14) | (head[8] << 7) | head[9]) if head[:3] == b"ID3" else 0
    data = read_range(url, offset, 4096)
    i = next(i for i in range(len(data) - 4) if data[i] == 0xFF and data[i + 1] & 0xE0 == 0xE0
             and (data[i + 1] >> 1) & 3 == 1 and data[i + 2] >> 4 not in (0, 15) and (data[i + 2] >> 2) & 3 != 3)
    version_id, bitrate_index = (data[i + 1] >> 3) & 3, data[i + 2] >> 4
    mpeg1, mono = version_id == 3, data[i + 3] >> 6 == 3
    kbps = (MPEG1_KBPS if mpeg1 else MPEG2_KBPS)[bitrate_index]
    rate = SAMPLE_RATES[version_id][(data[i + 2] >> 2) & 3]
    xing = i + 4 + ((17 if mono else 32) if mpeg1 else (9 if mono else 17))
    if data[xing:xing + 4] in (b"Xing", b"Info") and data[xing + 7] & 1:
        frames = int.from_bytes(data[xing + 8:xing + 12], "big")
        return frames * (1152 if mpeg1 else 576) / rate
    return (size - offset) * 8 / (kbps * 1000)


def check_file(entry: dict) -> str | None:
    surah = entry["chapter_id"]
    try:
        with request(entry["audio_url"], "HEAD") as response:
            kind = response.headers.get("Content-Type", "")
            size = int(response.headers.get("Content-Length", "-1"))
        if response.status != 200 or kind != "audio/mpeg" or size < 10_000:
            return f"surah {surah}: HTTP {response.status} {kind} {size} bytes"
        entry["verified_bytes"] = size
        entry["seconds"] = round(mp3_seconds(entry["audio_url"], size), 1)
    except urllib.error.HTTPError as error:
        return f"surah {surah}: HTTP {error.code}"
    except (StopIteration, IndexError, KeyError):
        return f"surah {surah}: no readable MP3 frame"
    return None


def verify(reciter: dict, files: list[dict]) -> list[str]:
    files = [f for f in files if f.get("chapter_id") and f.get("audio_url")]
    problems = []
    if sorted(f["chapter_id"] for f in files) != list(range(1, 115)):
        problems.append(f"{len(files)} recordings instead of one per surah")
    urls = [urlparse(f["audio_url"]) for f in files]
    if any(u.scheme != "https" or u.netloc != AUDIO_HOST for u in urls):
        problems.append(f"files outside https://{AUDIO_HOST}")
    folders = {u.path.rsplit("/", 1)[0] for u in urls}
    if len(folders) != 1:
        problems.append(f"files span {len(folders)} folders: {sorted(folders)[:3]}")
    if not problems:
        with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
            problems += [p for p in pool.map(check_file, files) if p]
    if not problems:
        pace = {f["chapter_id"]: f["seconds"] / WORDS[f["chapter_id"]] for f in files}
        median = sorted(pace.values())[len(pace) // 2]
        problems += [f"surah {s}: {pace[s] / median:.2f}x the reciter's usual pace ({files_by(files)[s]['seconds']:.0f}s)"
                     for s in sorted(pace) if not 0.5 <= pace[s] / median <= 2]
    return problems


def files_by(files: list[dict]) -> dict[int, dict]:
    return {f["chapter_id"]: f for f in files}


def main() -> None:
    english = get_json(f"{API}/resources/recitations?language=en")["recitations"]
    arabic = {r["id"]: r["translated_name"]["name"] for r in get_json(f"{API}/resources/recitations?language=ar")["recitations"]}
    reciters, errors = [], []
    for reciter in english:
        files = get_json(f"{API}/chapter_recitations/{reciter['id']}")["audio_files"]
        problems = verify(reciter, files)
        label = f"{reciter['reciter_name']} ({reciter['style'] or 'Murattal'}, id {reciter['id']})"
        if reciter["id"] in EXCLUDED:
            if not problems:
                errors.append(f"{label} now passes; re-check it and remove it from EXCLUDED")
            print(f"Excluded {label}: {EXCLUDED[reciter['id']]}")
            continue
        if problems:
            errors.append(f"{label}: " + "; ".join(problems[:3]))
            continue
        surahs = sorted((f for f in files if f.get("chapter_id") and f.get("audio_url")), key=lambda f: f["chapter_id"])
        reciters.append({
            "id": reciter["id"],
            "name": reciter["reciter_name"],
            "arabicName": arabic[reciter["id"]],
            "style": reciter["style"] or "Murattal",
            "surahs": [{"surah": f["chapter_id"], "url": f["audio_url"], "seconds": f["seconds"]} for f in surahs],
        })
        print(f"Verified {label}: 114 surahs, {sum(f['seconds'] for f in surahs) / 3600:.1f} hours")
    if errors:
        print(f"Recitation verification failed; nothing was written.", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        sys.exit(1)
    OUTPUT.write_text(json.dumps({
        "source": "Quran Foundation recitations (api.quran.com), streamed from download.quranicaudio.com",
        "verified": datetime.date.today().isoformat(),
        "reciters": reciters,
    }, ensure_ascii=False, separators=(",", ":")))
    print(f"Wrote {len(reciters)} verified reciters to {OUTPUT.relative_to(ROOT)}.")


if __name__ == "__main__":
    main()
