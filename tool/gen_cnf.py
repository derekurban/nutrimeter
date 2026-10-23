"""Generate mobile/assets/cnf/foods.json from Health Canada's Canadian Nutrient File (CNF) 2026.

Usage (from the repo root; stdlib only, Python 3.10+):

    python -I tool/gen_cnf.py                       # download the CNF zip into data/cnf/raw/ (if absent) and build
    python -I tool/gen_cnf.py --src PATH            # PATH = the CNF "All Resource Data" zip, or a dir of its CSVs
    python -I tool/gen_cnf.py --force-download      # re-download the zip even if it is already present
    python -I tool/gen_cnf.py --out other.json      # write somewhere else (default: mobile/assets/cnf/foods.json)

The downloaded files are treated as data only: CSVs are read straight out of the zip, nothing
in it is extracted or executed. Prints food count, asset size, per-nutrient coverage and
sanity spot-checks. See data/cnf/README.md for the nutrient mapping and judgement calls.
"""

from __future__ import annotations

import argparse
import csv
import datetime as _dt
import io
import json
import os
import re
import sys
import urllib.request
import zipfile
from collections import defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_RAW_DIR = os.path.join(REPO, "data", "cnf", "raw")
DEFAULT_OUT = os.path.join(REPO, "mobile", "assets", "cnf", "foods.json")
ZIP_NAME = "cnf_fcen_all-files-data_2026.zip"

DATASET_ID = "1b6139bd-ed7e-4043-bc28-ff00e10f3109"
CKAN_API = f"https://open.canada.ca/data/api/action/package_show?id={DATASET_ID}"
FALLBACK_ZIP_URL = (
    f"https://open.canada.ca/data/dataset/{DATASET_ID}/resource/"
    "019f2a90-e3a9-489d-b6e1-f74f4ba1d006/download/cnf_fcen_all-files-data_2026.zip"
)

SOURCE = "Canadian Nutrient File 2026, Health Canada"
LICENCE = "Open Government Licence - Canada"  # exact title on the open.canada.ca dataset record
LICENCE_URL = "https://open.canada.ca/en/open-government-licence-canada"
ATTRIBUTION = (
    "Contains information licensed under the Open Government Licence – Canada. "
    "Source: Canadian Nutrient File, Health Canada, 2026."
)

# (our key, expected CNF unit, rule). Rule is either a list of CNF nutrient codes tried in order
# (first present wins; optional per-code multiplier), a special-case string, or None (no CNF data).
NUTRIENTS: list[tuple[str, str, object]] = [
    ("energy", "kilocalorie", [("208", 1.0)]),
    ("caffeine", "Milligram", [("262", 1.0)]),
    ("carbs", "Gram", [("205", 1.0)]),
    ("fiber", "Gram", [("291", 1.0)]),
    ("starch", "Gram", None),          # code 209 removed from CNF in 2026
    ("sugars", "Gram", [("269", 1.0)]),
    ("addedSugars", "Gram", None),     # not in CNF
    ("fat", "Gram", [("204", 1.0)]),
    ("satFat", "Gram", [("606", 1.0)]),
    ("monoFat", "Gram", [("645", 1.0)]),
    ("polyFat", "Gram", [("646", 1.0)]),
    ("omega3", "Gram", "omega3"),      # codes 902/903 (total n-3/n-6) removed in 2026: summed
    ("omega6", "Gram", "omega6"),
    ("transFat", "Gram", [("605", 1.0)]),
    ("cholesterol", "Milligram", [("601", 1.0)]),
    ("protein", "Gram", [("203", 1.0)]),
    ("vitA", "Microgram", [("320", 1.0)]),
    ("vitB1", "Milligram", [("404", 1.0)]),
    ("vitB2", "Milligram", [("405", 1.0)]),
    ("vitB3", "Milligram", [("406", 1.0), ("409", 1.0)]),   # preformed niacin; NE only if that's all
    ("vitB5", "Milligram", [("410", 1.0)]),
    ("vitB6", "Milligram", [("415", 1.0)]),
    ("vitB12", "Microgram", [("418", 1.0)]),
    ("biotin", "Microgram", [("416", 1.0)]),
    ("folate", "Microgram", [("435", 1.0), ("417", 1.0)]),  # DFE; total folacin if no DFE
    ("vitC", "Milligram", [("401", 1.0)]),
    ("vitD", "Microgram", [("328", 1.0), ("324", 1 / 40)]),  # ug D2+D3; IU/40 if only IU
    ("vitE", "Milligram", [("323", 1.0)]),
    ("vitK", "Microgram", [("430", 1.0)]),  # phylloquinone (K1)
    ("calcium", "Milligram", [("301", 1.0)]),
    ("copper", "Milligram", [("312", 1.0)]),
    ("iron", "Milligram", [("303", 1.0)]),
    ("magnesium", "Milligram", [("304", 1.0)]),
    ("manganese", "Milligram", [("315", 1.0)]),
    ("phosphorus", "Milligram", [("305", 1.0)]),
    ("potassium", "Milligram", [("306", 1.0)]),
    ("selenium", "Microgram", [("317", 1.0)]),
    ("sodium", "Milligram", [("307", 1.0)]),
    ("zinc", "Milligram", [("309", 1.0)]),
]
# Fallback units that are allowed for a code even though they differ from our unit.
ALLOWED_UNIT_EXCEPTIONS = {"409": "Niacin Equivalents", "324": "International Unit"}

# Fatty-acid components (all grams per 100 g). Each entry: preferred code, or fallback
# (undifferentiated total code, codes of other isomers to subtract from it).
N3_PARTS = [
    ("851", ("619", ["685", "856"])),  # 18:3 n-3 ALA; else 18:3 undiff minus GLA (n-6) and 18:3i
    ("627", None),                     # 18:4 (stearidonic acid, n-3)
    ("852", None),                     # 20:3 n-3
    ("629", None),                     # 20:5 n-3 EPA
    ("631", None),                     # 22:5 n-3 DPA
    ("621", None),                     # 22:6 n-3 DHA
]
N6_PARTS = [
    ("675", ("618", ["665", "666", "669", "670", "910", "911", "912"])),  # 18:2 c,c n-6 LA
    ("685", None),                     # 18:3 n-6 GLA
    ("672", None),                     # 20:2 c,c (n-6)
    ("853", None),                     # 20:3 n-6
    ("855", ("620", [])),              # 20:4 n-6 AA; else 20:4 undiff
    ("858", None),                     # 22:4 n-6
    ("913", None),                     # 22:5 n-6
]

USER_DEFINED_MEASURE = "6"  # Measure_Type 3 = refuse, 9 = yield; only 6 are servings
# Only "100 g" is redundant (the app always offers grams); "100 ml" is a real volume measure and stays.
DROP_MEASURE_RE = re.compile(r"^100\s*g$", re.I)


def measure_rank(m):
    """Order a food's measures so the first is the natural default serving in the app:
    "1 medium", then other single pieces ("1 slice", "1 large"), then 250 ml, then the rest (stable)."""
    label = m[0].lower()
    if label.startswith("1 medium"):
        return 0
    if re.match(r"^1 (?!.*ml)", label):
        return 1
    if label.startswith("250 ml"):
        return 2
    return 3

SPOT_CHECKS = [
    (1704, "raw banana", {"energy": (89, 97), "potassium": (350, 360), "vitC": (8, 9)}),
    (61, "2% milk", {"calcium": (110, 130), "vitD": (0.8, 1.3)}),
    (841, "raw chicken breast", {"protein": (21, 23)}),
]


def round4(x: float):
    if x == 0:
        return 0
    v = float(f"{x:.4g}")
    return int(v) if v.is_integer() and abs(v) < 1e15 else v


def clean_label(s: str) -> str:
    s = re.sub(r"\s+", " ", s).strip()
    letters = [c for c in s if c.isalpha()]
    if len(letters) > 3 and all(c.isupper() for c in letters):
        s = s.lower()
    return s


class Source:
    """Reads CNF CSVs from either the official zip or a directory of extracted CSVs."""

    def __init__(self, path: str):
        self.path = path
        self.zip = zipfile.ZipFile(path) if os.path.isfile(path) else None
        names = self.zip.namelist() if self.zip else os.listdir(path)
        self.names = {os.path.basename(n).lower(): n for n in names}

    def rows(self, name: str):
        key = name.lower()
        if key not in self.names:
            sys.exit(f"error: {name} not found in {self.path}")
        if self.zip:
            raw = self.zip.read(self.names[key])
        else:
            with open(os.path.join(self.path, self.names[key]), "rb") as f:
                raw = f.read()
        return list(csv.DictReader(io.StringIO(raw.decode("utf-8-sig"), newline="")))


def find_zip_url() -> str:
    try:
        with urllib.request.urlopen(CKAN_API, timeout=60) as r:
            pkg = json.load(r)["result"]
        if pkg.get("license_title") != LICENCE:
            print(f"WARNING: dataset licence is now {pkg.get('license_title')!r}; update LICENCE",
                  file=sys.stderr)
        for res in pkg.get("resources", []):
            url = res.get("url", "")
            if res.get("format", "").upper() == "ZIP" and "all-files" in url:
                return url
    except Exception as e:  # network/API trouble: use the known URL
        print(f"note: CKAN lookup failed ({e}); using known zip URL", file=sys.stderr)
    return FALLBACK_ZIP_URL


def download(raw_dir: str, force: bool) -> str:
    os.makedirs(raw_dir, exist_ok=True)
    dest = os.path.join(raw_dir, ZIP_NAME)
    if os.path.exists(dest) and not force:
        print(f"using existing {dest}")
        return dest
    url = find_zip_url()
    print(f"downloading {url}")
    tmp = dest + ".part"
    with urllib.request.urlopen(url, timeout=300) as r, open(tmp, "wb") as f:
        while chunk := r.read(1 << 20):
            f.write(chunk)
    os.replace(tmp, dest)
    return dest


def fatty_sum(v: dict, parts) -> float | None:
    total, any_present = 0.0, False
    for code, fallback in parts:
        if code in v:
            total += v[code]
            any_present = True
        elif fallback and fallback[0] in v:
            undiff, minus = fallback
            total += max(0.0, v[undiff] - sum(v.get(c, 0.0) for c in minus))
            any_present = True
    return total if any_present else None


def build(src: Source):
    groups = {r["CNF_Food_Group_Code"]: r["CNF_Food_Group_Description_EN"].strip()
              for r in src.rows("CNF_Food_Group.csv")}
    units = {r["Nutrient_Code"]: r["Nutrient_Unit"] for r in src.rows("Nutrient_Name.csv")}
    for key, unit, rule in NUTRIENTS:
        if isinstance(rule, list):
            for code, _ in rule:
                want = ALLOWED_UNIT_EXCEPTIONS.get(code, unit)
                if units.get(code) != want:
                    sys.exit(f"error: {key}: CNF code {code} unit {units.get(code)!r} != {want!r}")
    for code, fb in N3_PARTS + N6_PARTS:
        for c in [code] + ([fb[0]] + fb[1] if fb else []):
            if units.get(c) != "Gram":
                sys.exit(f"error: fatty acid code {c} unit {units.get(c)!r} != 'Gram'")

    amounts: dict[str, dict[str, float]] = defaultdict(dict)
    for r in src.rows("Nutrient_Amount.csv"):
        amounts[r["Food_Code"]][r["Nutrient_Code"]] = float(r["Nutrient_Amount"])

    measure_names = {r["Measure_Code"]: r["Measure_Description_and_Unit_EN"]
                     for r in src.rows("Measure_Name.csv")}
    measures: dict[str, list] = defaultdict(list)
    stats = defaultdict(int)
    for r in src.rows("Measure_Weight_Conversion.csv"):
        if r["Measure_Type_Code"] != USER_DEFINED_MEASURE:
            continue
        name = measure_names.get(r["Measure_Code"])
        if not name:
            stats["measures_without_name"] += 1
            continue
        label = clean_label(name)
        grams = float(r["Measure_Weight_Conversion"])  # 2026: already grams (not a x100 factor)
        if DROP_MEASURE_RE.match(label):
            stats["dropped_100"] += 1
            continue
        if grams <= 0:
            stats["nonpositive_measures"] += 1
            continue
        measures[r["Food_Code"]].append([label, round4(grams)])

    fallbacks = defaultdict(list)
    foods = []
    for r in src.rows("Food_Name.csv"):
        code = r["Food_Code"]
        v = amounts.get(code, {})
        n = []
        for key, _unit, rule in NUTRIENTS:
            val = None
            if rule == "omega3":
                val = fatty_sum(v, N3_PARTS)
            elif rule == "omega6":
                val = fatty_sum(v, N6_PARTS)
            elif isinstance(rule, list):
                for i, (c, mult) in enumerate(rule):
                    if c in v:
                        val = v[c] * mult
                        if i > 0:
                            fallbacks[key].append(int(code))
                        break
            n.append(None if val is None else round4(val))
        foods.append({
            "id": int(code),
            "en": clean_label(r["Food_Description_EN"]),
            "fr": clean_label(r["Food_Description_FR"]),
            "group": groups.get(r["CNF_Food_Group_Code"], ""),
            "n": n,
            "m": sorted(measures.get(code, []), key=measure_rank),
        })
    foods.sort(key=lambda f: f["id"])
    return foods, fallbacks, stats


def report(foods, fallbacks, stats, out_path):
    keys = [k for k, _, _ in NUTRIENTS]
    print(f"\nfoods: {len(foods)}")
    print(f"asset: {out_path} ({os.path.getsize(out_path) / 1024:.0f} KB)")
    print("\ncoverage (% foods with non-null value):")
    for i, k in enumerate(keys):
        pct = 100 * sum(1 for f in foods if f["n"][i] is not None) / len(foods)
        print(f"  {k:<12} {pct:5.1f}%")
    for k, ids in fallbacks.items():
        print(f"fallback source used for {k}: {len(ids)} foods (e.g. {ids[:5]})")
    for k, v in sorted(stats.items()):
        print(f"{k}: {v}")
    print(f"foods without any household measure: {sum(1 for f in foods if not f['m'])}")
    by_id = {f["id"]: f for f in foods}
    print("\nspot checks:")
    for fid, label, expect in SPOT_CHECKS:
        f = by_id.get(fid)
        if not f:
            print(f"  {label}: food {fid} MISSING")
            continue
        print(f"  {label} [{fid}] {f['en']!r}")
        for k, (lo, hi) in expect.items():
            val = f["n"][keys.index(k)]
            ok = val is not None and lo <= val <= hi
            print(f"    {k} = {val}  (expect {lo}-{hi}) {'OK' if ok else 'CHECK'}")
    if 1704 in by_id:
        print("\nbanana measures:", by_id[1704]["m"])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", help="CNF zip or directory of CNF CSVs (default: download)")
    ap.add_argument("--raw-dir", default=DEFAULT_RAW_DIR, help="download directory")
    ap.add_argument("--force-download", action="store_true")
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()

    src_path = args.src or download(args.raw_dir, args.force_download)
    foods, fallbacks, stats = build(Source(src_path))
    doc = {
        "source": SOURCE,
        "licence": LICENCE,
        "licenceUrl": LICENCE_URL,
        "attribution": ATTRIBUTION,
        "generated": _dt.date.today().isoformat(),
        "nutrients": [k for k, _, _ in NUTRIENTS],
        "foods": foods,
    }
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    report(foods, fallbacks, stats, args.out)


if __name__ == "__main__":
    main()
