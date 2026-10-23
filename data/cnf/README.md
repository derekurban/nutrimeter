# Canadian Nutrient File (CNF) asset

`mobile/assets/cnf/foods.json` is generated from Health Canada's **Canadian Nutrient File, 2026 edition**
by `tool/gen_cnf.py`. It covers 5,993 generic foods, with values per 100 g of edible portion.

## Source

- Dataset: "Canadian Nutrient File, 2026" on the Open Government Portal,
  https://open.canada.ca/data/en/dataset/1b6139bd-ed7e-4043-bc28-ff00e10f3109
- File used: "All Resource Data" zip `cnf_fcen_all-files-data_2026.zip`
  (resource last modified 2026-06-03; the CSVs inside are dated 2026-05-08). Downloaded 2026-10-23.
- Files read: `Food_Name.csv`, `CNF_Food_Group.csv`, `Nutrient_Name.csv`, `Nutrient_Amount.csv`,
  `Measure_Name.csv`, `Measure_Weight_Conversion.csv`. These come from the zip. The PDFs in it
  (users' guide, database structure) are the documentation.
- About page: https://www.canada.ca/en/health-canada/services/food-nutrition/healthy-eating/nutrient-data/canadian-nutrient-file-about-us.html

## Licence and attribution

- Licence (exact title on the dataset record): **Open Government Licence - Canada** (version 2.0),
  https://open.canada.ca/en/open-government-licence-canada
- The licence requires the provider's attribution statement, or by default:
  "Contains information licensed under the Open Government Licence – Canada."
- Health Canada's CNF copyright guidelines (users' guide, p. 45) ask that Health Canada be named as the
  source as "Canadian Nutrient File, Health Canada, 2026". The guidelines also say: don't modify nutrient
  values (showing them for other serving sizes is allowed), don't present the data as official or
  endorsed by Health Canada, and treat the CNF as a reference tool, not medical advice.
- Attribution text in the asset (show it in the app's about/credits screen):

  > Contains information licensed under the Open Government Licence – Canada. Source: Canadian Nutrient File, Health Canada, 2026.

## Regenerating

From the repo root:

```sh
python -I tool/gen_cnf.py                    # downloads the zip into data/cnf/raw/ if missing, then builds
python -I tool/gen_cnf.py --force-download   # fetch a fresh copy first
python -I tool/gen_cnf.py --src path/to/cnf_fcen_all-files-data_2026.zip   # or a directory of the CSVs
```

The script uses only the Python standard library. It finds the zip URL through the CKAN API, and uses a
built-in URL if the API is unreachable. It reads the CSVs straight from the zip without extracting
anything, and warns if the dataset licence has changed. `data/cnf/raw/` is git-ignored. The script
checks every mapped CNF code's unit against the expected unit and stops if one doesn't match. When it
finishes it prints coverage, spot checks and the banana measures.

## Schema notes

- `nutrients[i]` names the value at `foods[].n[i]`. Values are per 100 g, in the units below, rounded to
  4 significant digits. `null` means CNF has no value; CNF says a missing value is unknown, not zero.
- `m` is a list of `[label, grams]` pairs, using only CNF's **user-defined** measures (Measure_Type 6).
  Refuse (type 3, e.g. "total refuse", "skin") and yield (type 9, e.g. "500 g of raw whole bird")
  entries are not servings, so they are left out. Measures keep the source file order. Grams are rounded to 4 significant digits.
- Foods are sorted by `id` (= CNF `Food_Code`).

## Nutrient mapping

| our key | unit | CNF code (symbol) – name, CNF unit | conversion |
|---|---|---|---|
| energy | kcal | 208 (KCAL) – Energy (kilocalories), kilocalorie | none (kJ code 268 not used; every food has 208) |
| caffeine | mg | 262 (CAFF) – Caffeine, mg | none |
| carbs | g | 205 (CARB) – Carbohydrate, total (by difference), g | none |
| fiber | g | 291 (TDF) – Fibre, total dietary, g | none |
| starch | g | **none**: code 209 STAR was removed in the 2026 edition | always null |
| sugars | g | 269 (TSUG) – Sugars, total, g | none |
| addedSugars | g | **none**: not in CNF | always null |
| fat | g | 204 (FAT) – Fat (total lipids), g | none |
| satFat | g | 606 (TSAT) – Fatty acids, saturated, total, g | none |
| monoFat | g | 645 (MUFA) – Fatty acids, monounsaturated, total, g | none |
| polyFat | g | 646 (PUFA) – Fatty acids, polyunsaturated, total, g | none |
| omega3 | g | sum of n-3 fatty acids (see below); totals 902/903 were removed in 2026 | sum |
| omega6 | g | sum of n-6 fatty acids (see below) | sum |
| transFat | g | 605 (TRFA) – Fatty acids, trans, total, g | none |
| cholesterol | mg | 601 (CHOL) – Cholesterol, mg | none |
| protein | g | 203 (PROT) – Protein, g | none |
| vitA | µg RAE | 320 (RAE) – Retinol activity equivalents, µg | none |
| vitB1 | mg | 404 (THIA) – Thiamine, mg | none |
| vitB2 | mg | 405 (RIBO) – Riboflavin, mg | none |
| vitB3 | mg | 406 (N-MG) – Niacin (nicotinic acid) preformed, mg; **fallback** 409 (N-NE) – Total niacin equivalent, NE | none (NE fallback only for foods 1584 and 7776) |
| vitB5 | mg | 410 (PANT) – Pantothenic acid, mg | none |
| vitB6 | mg | 415 (B6) – Vitamin B-6, mg | none |
| vitB12 | µg | 418 (B12) – Vitamin B-12, µg | none |
| biotin | µg | 416 (BIOT) – Biotin, µg | none (only 116 foods have it) |
| folate | µg DFE | 435 (DFE) – Dietary folate equivalents, µg; **fallback** 417 (FOLA) – Total folacin, µg | none (total-folacin fallback for 95 foods) |
| vitC | mg | 401 (VITC) – Vitamin C, mg | none |
| vitD | µg | 328 (D3+D2-µg) – Vitamin D (D2 + D3), µg; fallback 324 (D3+D2-IU) IU | IU ÷ 40 (never needed: every food with IU also has µg) |
| vitE | mg | 323 (ATMG) – Alpha-tocopherol, mg | none |
| vitK | µg | 430 (VITK) – Vitamin K (phylloquinone), µg | none |
| calcium | mg | 301 (CA) – Calcium, mg | none |
| copper | mg | 312 (CU) – Copper, mg | none |
| iron | mg | 303 (FE) – Iron, mg | none |
| magnesium | mg | 304 (MG) – Magnesium, mg | none |
| manganese | mg | 315 (MN) – Manganese, mg | none |
| phosphorus | mg | 305 (P) – Phosphorus, mg | none |
| potassium | mg | 306 (K) – Potassium, mg | none |
| selenium | µg | 317 (SE) – Selenium, µg | none |
| sodium | mg | 307 (NA) – Sodium, mg | none |
| zinc | mg | 309 (ZN) – Zinc, mg | none |

"Fallback" means the second code is used only when the first is missing for that food.

### Omega-3 / omega-6

The 2026 edition removed the total n-3 (902) and total n-6 (903) fields, so the script sums the
individual fatty acids that are present for each food. A sum is null only when none of its parts are present.

- **omega3** = ALA + 18:4 (627, stearidonic) + 20:3 n-3 (852) + EPA 20:5 n-3 (629) + DPA 22:5 n-3 (631) + DHA 22:6 n-3 (621).
  ALA is 851 (18:3 c,c,c n-3). If 851 is missing, ALA = 619 (18:3 undifferentiated) − 685 (GLA, n-6) − 856 (18:3i), floored at 0.
- **omega6** = LA + GLA 18:3 n-6 (685) + 20:2 c,c (672) + 20:3 n-6 (853) + AA + 22:4 n-6 (858) + 22:5 n-6 (913).
  LA is 675 (18:2 c,c n-6). If 675 is missing, LA = 618 (18:2 undifferentiated) − the other 18:2 isomers present
  (665 18:2t, 666 18:2i, 669 18:2t,t, 670 CLA, 910/911/912 9c13c/9c14c/9c15c), floored at 0.
  AA is 855 (20:4 n-6), or 620 (20:4 undifferentiated) if 855 is missing.
- I checked the fallbacks against foods that have both the total and the parts. The median difference is
  0%: 18:3 matches ALA+GLA+18:3i, 18:2 matches its isomers, and 20:4 matches AA.

## Measures

- In CNF 2026, `Measure_Weight_Conversion` is **already the weight in grams**, not a ×100 factor. The
  structure doc says the 2015 conversion factors "have been replaced by measure weight conversions where you
  do not have to multiply the portion size by 100". Their example is 250 ml applesauce: 2.57819 in 2015,
  257.819 g in 2026. So grams = the value as published. Checks: "1 medium" banana (food 1704) = 118 g, and
  250 ml of 2% milk (food 61) = 257.8 g (density ≈ 1.03). Multiplying by 100 would make a banana 11.8 kg.
- Labels are trimmed and runs of whitespace (including stray newlines) collapsed to one space. An
  all-caps label would be lowercased, but no 2026 measure label is all caps.
- Labels that are exactly `100 g` are dropped, since the app always offers grams. `100 ml` is kept: it is a real
  volume measure and not the same as 100 g. Other plain gram presets such as `125 g` or `30 g` are kept.
- Each food's measures are ordered so the first is a natural default serving: `1 medium`, then other single
  pieces (`1 slice`, `1 large`), then `250 ml`, then the rest in source order (`measure_rank` in the script).
- One user-defined measure (food 1728, measure code 1116, 175 g) has no entry in Measure_Name.csv and is skipped.
- 108 foods have no household measures (they log in grams or ounces).

## Judgement calls

1. **Source version**: CNF 2026 (the current release), not 2015.
2. **Measure weights** are used as grams directly (see above). This overrides the "conversion factor × 100"
   instruction, which only applied to the 2015 files.
3. **Only user-defined measures** go into `m`. Refuse and yield rows are not servings.
4. **`100 ml` is kept** (it was dropped in a first pass): 100 ml is not 100 g, and for 24 foods it is the only
   volume measure, e.g. food 800 canned flaked chicken and the commercial pies 4075–4077.
5. **Niacin** = preformed niacin (406, mg). Niacin equivalents (409) are used only for foods 1584 and 7776,
   which have nothing else.
6. **Folate** = DFE (435). For the 95 foods without DFE, total folacin (417) is used. None of these 95 has
   both folic acid and food folate, so DFE can't be computed for them.
7. **Vitamin D** = 328 (D2+D3, µg). This excludes the 25-hydroxy metabolites (329/330), which CNF lists separately.
8. **Vitamin K** = phylloquinone (K1, 430) only. MK-4 (428, 151 foods) and dihydrophylloquinone (429, 70 foods) are not added in.
9. **Vitamin E** = alpha-tocopherol (323). Added alpha-tocopherol (573) is not added on top, because 323 is the total.
10. **Omega-3** includes 18:4 SDA and 20:3 n-3 as well as ALA/EPA/DPA/DHA. Omega-6 includes the minor
    n-6 acids. The undifferentiated fallbacks are described above.
11. **Starch, addedSugars**: always null, since CNF 2026 has no such field. **Biotin** is in CNF, but only for 116 foods (1.9%).
12. **Rounding** to 4 significant digits (the CNF guidelines ask that nutrient values not be modified; 4
    significant digits is at least the precision CNF itself shows for nearly all values). Computed omega sums are derived values, not CNF-published ones.
13. Food names are only whitespace-normalised. `group` is the English CNF food-group name, as given.

## Data quirks seen (source data, left as-is)

- **2% milk vitamin D is 1.94 µg/100 g** (77.6 IU), not about 1 µg. This reflects Canada's higher milk
  vitamin D fortification, and the record was updated 2026-01-28. Older references give about 1 µg.
- 33 foods have omega3 + omega6 greater than total PUFA, because the source fields disagree. For example,
  food 67 (dry buttermilk) has ALA (851) = 0.800 g but 18:3 total (619) = 0.084 g. Food 732 (turkey light
  meat) has 18:2 = 0.742 g but PUFA = 0.355 g.
- 59 foods have sat + mono + poly more than 5% above total fat (mostly turkey).
- 89 foods (mostly dried spices) have energy far below 4/4/9 × macros. CNF energy uses food-specific
  factors and handles fibre differently, so this isn't a bug.
- Some fields are mostly zeros. For example, caffeine is 0 for 5,470 of the 5,712 foods that have it.
