# Food model: records, taxonomy and how food gets in

Status: built on the dev branch, 2026-10-23. This records what we have decided, what is still open, and the
evidence collected so far. Companion documents:

- `measurements.md`: how amounts work (mass, volume, counts, preparation profiles), informed by Cronometer,
  MyFitnessPal and Canadian label rules.
- `taxonomy.md`: how records are indexed (USDA WWEIA groups, subgroups and categories), and why.
- `backend.md`: the auditable review pipeline and the Convex vs Supabase comparison.
- `stress-test.md`: 20 real products walked through an earlier draft of this model.
- `candidates.json`: the data for those 20 products.

## Why this exists

Nutrimeter logs food from three places today: the Canadian Nutrient File (CNF, bundled, 5,993 generic foods),
Open Food Facts (OFF, barcode and search) and your own custom foods and recipes. Each is a separate,
flat `Food` whose id names its source (`cnf:1696`, `off:<barcode>`, `custom:<id>`). So "Oreo", a no-name
chocolate sandwich cookie and CNF's "Cookie, chocolate sandwich" are three unrelated foods. A large egg from
CNF and a Safeway carton of eggs look and behave differently.

The person logging does not care where data came from. They care that the food gets logged and that the
insights are right. This document defines the shape that makes generic foods and products look like one
catalogue.

**Open Food Facts is dropped.** The stress test found OFF data that was marked complete but wrong (Nutella
sodium of 52.6 g per 100 g, peanut butter with 0 g protein, Kraft Dinner with only "prepared" values). Since
every product needs review anyway, every product goes through our own pipeline from photos. CNF remains the
source for generic foods.

It also absorbs the ideas from **foodcards** (`github.com/derekurban/foodcards`, private, last worked on
2026-09-10): one canonical reference per food with variants, a culinary browse taxonomy, and pastel clay
illustrations. Its SvelteKit curator gallery and import scripts are not carried over. Its taxonomy idea became
the WWEIA index; its clay art can become taxonomy images.

## Principles

1. **Source is invisible.** The display never says "CNF" or names a pipeline. It shows a food, an optional
   brand, and its numbers.
2. **Generic first, barcode for accuracy.** Searching "egg" gives the best generic bet straight away. Scanning
   a carton gives that carton's label. Both look the same.
3. **No backfill.** A record shows what its own source knows. Unknown is "—", never borrowed from a sibling or
   the generic. The fix for a partial record is to complete it through intake.
4. **Images are cosmetic and belong to the taxonomy, never to records.** No product art (copyright, cost); a
   record shows its category's, subgroup's or group's image.
5. **Identity outlives data.** A food's id is minted the moment you first scan or name it, before anything is
   known, and stays the same through review and publication.
6. **Every published number traces to evidence.** For products that means your photos; for generic foods, the
   CNF row.

## The model

Decided 2026-10-23, replacing the earlier concept layer: **records are the catalogue; the taxonomy only indexes
them.** There is no "concept" of a food between the two.

### Record

A measurement of one food from one source: `cnf:<code>` (bundled in the app), `gtin:<14 digits>` (a barcoded
product), `food:<slug>` (a reviewed product with no barcode), `custom:<id>`, `recipe:<id>`, and `pending:<uuid>`
(a search miss not reviewed yet). A published record holds:

- a **role**: `generic` or `product`. Role is separate from source: some CNF rows are products ("Cheerios,
  General Mills");
- one or more **nutrition profiles** (as sold, prepared, drained), always per 100 g, with portions in grams and
  the label as printed beside them (`measurements.md`);
- name, brand, qualifiers (0%, salted, thin), barcodes, package size and ingredients;
- its **category** (below), or none;
- a current revision; every revision links to the review, the AI attempt and the photos it came from.

Barcodes are normalised to GTIN-14 by symbology: 8-digit UPC-E is expanded to UPC-A first, never zero-padded.
The raw code and symbology are kept.

### Taxonomy

```
Group       Grains                         15, from USDA WWEIA, fixed
Subgroup    Ready-to-Eat Cereals           49, from USDA WWEIA, fixed
Category    Ready-to-eat cereal            164, from USDA WWEIA (threshold splits merged); new ones only by a person
Record      Cheerios · General Mills       category_id = ready-to-eat-cereal, or null
```

- A record's `category_id` is **null** (uncategorized, our "Other") or **one category**, which implies its
  subgroup and group. There is no partial classification.
- **The AI picks a category or null; it cannot create one.** Adding categories is a separate review stream,
  not built yet.
- A reviewer can re-file a published record (`set_record_category`) without a new revision; the reason goes in
  the event log.
- **Images are cosmetic and never belong to a record.** Groups, subgroups and categories may each have one; a
  record shows its category's image, else its subgroup's, else its group's, else a letter placeholder.
- Rules, sources and the comparison with GS1 GPC, FoodEx2 and LanguaL: `taxonomy.md`.

### Alias

`old id → new id`. Covers a `pending:` search miss once it is published, duplicates merged in review,
repackaged products with new barcodes, and the app's old `off:<barcode>` ids. The diary stores record ids and
resolves through aliases.

### Display and resolution

- A row shows the record's name, its brand as the subtitle ("Generic" for a generic record), and the taxonomy
  image. The food page shows "Group › Subgroup › Category", or "Uncategorized".
- **Search "egg"** finds records by name and brand, and also by their category, subgroup and group names, so
  "cereal" finds Cheerios.
- **Scan** → barcode → record (through aliases).
- **Scan or search miss** → a provisional record, logged by name and grams today; review fills it in under the
  same id (`gtin:`) or through an alias (`pending:`).

## Getting food in

```
scan / search miss
   │
   ▼
PROVISIONAL (on the device)   id minted; name + amount + your photos; loggable now
   │  app uploads
   ▼
QUEUED ─► CLAIMED (agent) ─► DRAFTED (extraction) ─► ACCEPTED (your review) ─► on the device, same id
                                      │                    │
                                      │                    └─► REJECTED (back to queued, with notes)
                                      └─► MERGED-INTO (alias to an existing record)
```

1. You scan a barcode, or search and find nothing.
2. The app walks you through the photos: front (name, brand, net quantity), the Nutrition Facts table, and
   ingredients. You can log the food immediately by name and amount.
3. The app uploads the photos and the submission to the backend (`backend.md`).
4. An agent on a schedule claims queued submissions. It reads the photos, records the label as printed,
   derives the per-100 values and profiles, runs automated checks (energy against macros, values within
   physical limits, serving against net quantity), and picks a category or none.
5. You review on the phone: each photo beside its extracted table, then accept, edit or reject. Accepting is
   the only way anything is published, and it records who accepted what, when, from which extraction and
   which photos.
6. The published record syncs to the app and the provisional record fills in under the same id. Portions
   follow the review ("1 pouch" becomes the label's 113 g); amounts you weighed never change.

Cronometer runs the same flow for missing products: front and label photos, an AI read, then review by their
curation team, with the food loggable as a custom food meanwhile (`measurements.md` has sources).


## Decisions so far

| Question | Decision |
|---|---|
| Open Food Facts | **Dropped.** Every product comes from your photos through review. |
| Fill a product's missing nutrients from its generic? | **No.** Show unknown as unknown. |
| Preparation forms | Profiles on one record (as sold, prepared, drained), or separate records. Never inferred. |
| Composite products | One record. |
| Classification | USDA WWEIA groups, subgroups and categories (threshold splits merged); a record has one category or none. The AI never creates categories. |
| Images | Cosmetic, on the taxonomy only, with category → subgroup → group fallback. |
| Every food has grams | Nutrition per 100 g; volume labels get a reviewed density. |
| What search returns | The generic default. Brands arrive by barcode. No learned "usual brand". |
| Ids | Identity-based (`gtin:`, `food:`, `pending:`, `cnf:`, `custom:`, `recipe:`) with an alias table. |
| Audit | Photos, extractions and reviews are kept forever and linked to every published revision. |
| Foodcards infrastructure | The SvelteKit gallery and Bun import scripts are retired. |

## Open questions

- **History.** When a published record is corrected, do past diary entries take the new numbers (weighed
  amounts aside), or keep the numbers they were logged with? Today they take the new numbers.
- **Category stream.** How new categories are proposed and reviewed, and which to add first (herbs and spices,
  mushrooms, seaweed have no WWEIA category of their own).
- **Merging duplicates.** The review site cannot yet merge a submission into an existing record.

## Removing Open Food Facts from the app

`mobile/lib/services/off.dart`, OFF text search, `FoodSource.off`, the OFF parsing tests, and OFF's
attribution in Settings and the README go away. This lands in the same change as the capture flow, so a scan
miss always has somewhere to go. Existing `off:<barcode>` foods become provisional `gtin:` records through
aliases.

## Stress-test candidates

OFF is no longer a data source, but its products made good test material: twenty real Canadian products,
chosen to hit edge cases. Selection used OFF's search-a-licious endpoint (the main
v2 search returned "temporarily unavailable" on 2026-10-23): Canada, sorted by scans, and only products whose
OFF state is `nutrition-facts-completed`. Each product was then fetched in full from the v2 product API.
CNF candidates come from a name search over the bundled asset: they are possible matches, not decisions.
Full extracts are in `candidates.json`.

| # | Barcode | Product | Why it's here | CNF candidates |
|---|---|---|---|---|
| 1 | 0096619845774 | Kirkland Signature Organic Eggs, Large | Generic overlap; label 132 kcal/100 g vs CNF 152 | 125, 129, 130 |
| 2 | 0068700011016 | Dairyland 2% milk, 4 L | Generic overlap; sold by volume, "1 cup" serving | 61 |
| 3 | 0056800664812 | Oikos plain Greek yogurt | Generic overlap; CNF splits by fat % | 6979, 7469 |
| 4 | 0068100084276 | Kraft Smooth Peanut Butter | Generic overlap; crowded category | 3399, 3414 |
| 5 | 0055577101018 | Quaker Large Flake Oats | CNF itself names the brand; dry vs prepared | 1464, 1465, 1462 |
| 6 | 0681131861410 | Great Value chick peas, canned | Label per 125 mL; CNF splits drained vs not | 3279, 7060, 7242 |
| 7 | 0066721026590 | Oreo | Brand product with a generic | 3819 |
| 8 | 0667888380534 | Biskwi chocolate vanilla cookies | No-name knock-off of #7 | 3819 |
| 9 | 0626027811025 | Earth's Own Oat Original | Plant milk; CNF has only oat-and-quinoa | 7808 |
| 10 | 0096619796274 | Kirkland Chewy Protein Bar | No sensible generic; OFF quantity is "Kirkland" | none |
| 11 | 0057000010805 | Crave Pulled Chicken Burrito Bowl | Composite frozen meal; package = serving | none |
| 12 | 0068100904826 | Kraft Dinner Original | Sold dry, eaten prepared; OFF has only "prepared" values | 7140, 7141 |
| 13 | 0062020000842 | Nutella (Ferrero Canada) | Brand spread with a generic | 5736 |
| 14 | 0096619331130 | Kirkland hazelnut spread | Store-brand knock-off of #13 | 5736 |
| 15 | 06782900 | Coca-Cola, 355 mL | 8-digit UPC-E barcode; beverage in mL | 5288 |
| 16 | 0065633132818 | Cheerios | Brand that already exists inside CNF | 1475 |
| 17 | 0096619723829 | Kirkland dry roasted almonds | Generic overlap; CNF splits salted/unsalted | 2536, 2624 |
| 18 | 0060383837464 | PC 1 Year Aged Canadian Cheddar | Generic overlap; "1 year" maps ambiguously | 7737, 7735, 7734 |
| 19 | 0060383035822 | PC Hummus | Generic overlap; homemade vs commercial | 4870 |
| 20 | 0063400136274 | Wonder 100% Whole Wheat Thin Bread | Generic overlap; "2 slices (46 g)" serving | 4067, 7196 |

Seventeen of the twenty have a plausible CNF match (#1–8, #12–20). The oat drink (#9) has only a poor one,
and the protein bar and burrito bowl (#10–11) have none.

### Quirks already visible in the data

- **The label and the generic disagree.** Kirkland eggs are 132 kcal/100 g on the label; CNF raw egg is 152.
  Without backfill, the barcode wins for that record and CNF stays the generic.
- **CNF contains brands.** "Cereal, hot, oats (oatmeal), large flakes, dry, Quaker" and "Cheerios, General
  Mills" are CNF rows. A CNF row can therefore be a product, not a generic.
- **Prepared vs as sold.** Kraft Dinner has only `*_prepared` values in OFF (360 kcal per 85 g), which look
  like the dry-mix numbers. Nutrimeter's current OFF client reads `*_100g`, so this product would show no
  nutrition today.
- **Volume servings.** Milk is per 100 mL with "1 cup" (240 mL); chickpeas are per 125 mL; Coke is 355 mL.
  Grams need a density, or the record must accept millilitres.
- **Junk fields.** The protein bar's quantity is the string "Kirkland".
- **Barcode formats.** Coca-Cola's code is 8-digit UPC-E. GTINs need normalising (pad to 13 or 14 digits)
  before they become ids.
- **Ambiguous generics.** Cheddar aged one year could be CNF medium or old; chickpeas could be "solids and
  liquid" or "drained"; the oat drink's nearest CNF row is a blend.

## Sources

- Open Food Facts, data under the Open Database License. Products retrieved 2026-10-23.
- Canadian Nutrient File, Health Canada, 2026, under the Open Government Licence – Canada
  (`data/cnf/README.md`).
- foodcards repository, main at `94f4750` (2026-09-10).
