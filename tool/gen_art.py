"""Bundle the taxonomy pictures with the app: mobile/assets/art/<hash>.webp and mobile/assets/art/index.json.

Usage (from the repo root; stdlib only, Python 3.10+):

    python -I tool/gen_art.py

Reads the picture each group, subgroup and category shows in dev, staging and prod (the public taxonomy tables and
the public `taxonomy-art` bucket, with the publishable keys in mobile/lib/services/backend_config.dart), downloads
each one once and writes it under the hash of its bytes. index.json maps a picture's id (art/<id>.webp in the bucket)
to its file, so the app draws a picture from the bundle when it has it and from the network otherwise: a picture
accepted after this ran still shows, just not offline. Files no longer used are removed. Run it before a release.

The pictures are the admin's 256 px WebPs (about 10 KB each), so the whole set is about 2 MB.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import urllib.parse
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(REPO, "mobile", "lib", "services", "backend_config.dart")
OUT = os.path.join(REPO, "mobile", "assets", "art")
TABLES = ("food_groups", "food_subgroups", "food_categories")
ART_PATH = re.compile(r"^art/([0-9a-f-]{36})\.webp$")


def environments() -> list[tuple[str, str]]:
    """(url, publishable key) for each environment, as the app has them."""
    src = open(CONFIG, encoding="utf-8").read()
    found = re.findall(r"'(https://[a-z0-9]+\.supabase\.co)',\s*'(sb_publishable_[A-Za-z0-9_-]+)'", src)
    if len(found) != 3:
        sys.exit(f"expected three environments in {CONFIG}, found {len(found)}")
    return found


def get(url: str, key: str | None = None) -> bytes:
    headers = {"apikey": key, "Authorization": f"Bearer {key}"} if key else {}
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as r:
        return r.read()


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    index: dict[str, str] = {}
    by_sha: dict[str, str] = {}
    for url, key in environments():
        paths = set()
        for table in TABLES:
            for row in json.loads(get(f"{url}/rest/v1/{table}?select=image_path&image_path=not.is.null", key)):
                paths.add(row["image_path"])
        for path in sorted(paths):
            m = ART_PATH.match(path)
            if not m:
                print(f"  skipped {path}: not art/<id>.webp")
                continue
            body = get(f"{url}/storage/v1/object/public/taxonomy-art/{urllib.parse.quote(path)}")
            if body[:4] != b"RIFF" or body[8:12] != b"WEBP":
                sys.exit(f"{url} {path} is not a WebP")
            sha = hashlib.sha256(body).hexdigest()
            name = by_sha.get(sha)
            if name is None:
                name = by_sha[sha] = f"{sha[:16]}.webp"
                with open(os.path.join(OUT, name), "wb") as f:
                    f.write(body)
            index[m.group(1)] = name
        print(f"{url}: {len(paths)} pictures")

    with open(os.path.join(OUT, "index.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(dict(sorted(index.items())), f, indent=0, separators=(",", ":"))
        f.write("\n")
    keep = set(by_sha.values()) | {"index.json"}
    removed = [n for n in os.listdir(OUT) if n not in keep]
    for n in removed:
        os.remove(os.path.join(OUT, n))
    size = sum(os.path.getsize(os.path.join(OUT, n)) for n in keep)
    print(f"{len(by_sha)} files for {len(index)} picture ids, {size / 1024:.0f} KB; removed {len(removed)}")


if __name__ == "__main__":
    main()
