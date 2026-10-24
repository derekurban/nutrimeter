# Measurements: how amounts work

Status: draft, 2026-10-23. Covers how a food's nutrition is expressed and how a logged amount turns into
nutrients. Builds on the stress test (`stress-test.md`, gaps P0.1, P0.2, P0.6, P1.7, P1.8).

## What competitors do

### Cronometer

- **Weight is the base.** Every food in Cronometer must have gram weights. A serving is defined by its grams,
  and other servings (cup, tablespoon, piece) can only be added once a gram weight exists. Staff answers on the
  forum say volume measures are not converted automatically because density depends on cut and packing.
  ([liquid measurements](https://forums.cronometer.com/discussion/3324/liquid-measurements),
  [serving sizes for custom foods](https://forums.cronometer.com/discussion/2018/serving-sizes-for-custom-foods))
- **The cost of that rule shows up on branded drinks.** Labels often give a serving in mL with no grams, so
  Cronometer can store only that one serving size; staff suggest treating 1 mL as 1 g for water-like liquids.
  ([liquid measurements](https://forums.cronometer.com/discussion/comment/11803/))
- **Generic foods carry many measures.** Lab-analysed foods (NCCDB) come with weight-based and imperial
  measures, and staff recommend generic entries for that reason. The diary's unit dropdown lists the food's
  measures plus g.
  ([preferred serving size measurement](https://forums.cronometer.com/discussion/comment/809))
- **Recipes** can be weight-based or servings-based. Servings-based recipes exist for when ingredient weights
  are unknown: you measure the finished batch and log fractions of it.
  ([serving sizes in custom recipes](https://forums.cronometer.com/discussion/comment/7245))
- **Submission is photo-based and reviewed.** A missing packaged or restaurant food is created as a custom food
  (loggable straight away), then published with the barcode, a front photo (brand and name) and a nutrition
  label photo. An AI step reads the label; Cronometer's curation team reviews it before it joins their public
  database. Whole foods, homemade bread and recipes are excluded and stay custom.
  ([Publishing a food to the CRDB](https://support.cronometer.com/hc/en-us/articles/360018652672-Publishing-a-food-to-the-CRDB-Database),
  [barcode scanner](https://cronometer.com/blog/how-to-use-the-barcode-scanner/))

### MyFitnessPal

- **Entries are mostly user-generated**, so one food often has many competing entries; a green check marks
  verified ones, and guides tell users to prefer them.
  ([CSPI: how to pick a food-tracking app](https://www.cspinet.org/article/app-how-pick-food-tracking-app))
- **Each entry has its own serving list and a number-of-servings multiplier.** Serving options vary from entry
  to entry with little logic, so a common workaround is an entry defined per 1 g, logged as "number of servings"
  equal to grams eaten. Guides recommend grams and ounces over cups and spoons for accuracy.
  ([TechJunkie: change serving size](https://www.techjunkie.com/myfitnesspal-change-serving-size),
  [Lindenwood guide](https://www.lindenwood.edu/files/resources/my-fitness-pal.pdf))
- **Raw versus cooked** is a common logging error because nothing ties the two forms together.

These MyFitnessPal points come from third-party guides; I found no official help page on serving sizes.

### Canadian labels

The Nutrition Facts table states the serving as a household measure followed by its metric amount in **g or
mL** ("1 cup (250 mL)", "3 cookies (34 g)"). For a single-serving package the household measure is the whole
package. Serving sizes follow Health Canada's Table of Reference Amounts.
([Nutrition facts table](https://www.canada.ca/en/health-canada/services/food-labelling-changes/nutrition-facts-table.html),
[Table of reference amounts](https://www.canada.ca/en/health-canada/services/technical-documents-labelling-requirements/table-reference-amounts-food.html))

So a label gives us exactly one anchor per product: a serving in g *or* mL, rarely both.

## What we take from them

**Decision (2026-10-23): every food is grams-based.** Like Cronometer, nutrition is always per 100 g. Portions,
serving sizes and millilitres sit on top, each with its gram weight. Unlike Cronometer, a volume-only label is
not stuck with one serving: the review supplies a density, from the label when it prints both g and mL, or from a
named reference, and the source is recorded and flagged for the reviewer.

| Lesson | Source | What we do |
|---|---|---|
| Weight as the base keeps everything comparable | Cronometer | Nutrition is per 100 g, always. |
| Gram-only breaks for drinks | Cronometer | A volume label gets a reviewed density (`label` or `reference`), so mL portions still have grams. |
| Never guess density | Cronometer | No silent 1 mL = 1 g: the density's source and note are recorded, and a check flags non-label densities. |
| Generic foods need many measures | Cronometer | CNF measures stay on CNF records ("1 large egg", "250 ml, chopped"). |
| Duplicate entries are the main quality problem | MyFitnessPal | One record per barcode; concepts group brands; review gates everything. |
| Serving lists are inconsistent | MyFitnessPal | Every record offers g and oz plus its own named portions, each with grams. |
| Raw vs cooked is a common error | MyFitnessPal | Preparation states are separate profiles (or child concepts). |
| Photo submission with AI read and human review works | Cronometer | Same flow, with the food loggable while it waits. |
| Recipes need a servings mode | Cronometer | Keep the existing recipe servings. |

## The model

### On a record

Each nutrition profile in a published revision (`record_revisions.data.profiles[]`):

```jsonc
{
  "id": "as-sold",
  "heading": null,                                       // the label column, when there are several
  "serving": { "text": "Per 1 can (355 mL)", "grams": 369.2, "ml": 355 },
  "density_g_per_ml": 1.04, "density_source": "reference",   // "label" | "reference" | "none"
  "label": [ { "key": "energy", "amount": 140, "unit": "kcal", "percent_dv": null }, … ],  // as printed
  "per_100g": { "energy": 37.92, "carbs": 10.56, "sugars": 10.56, "sodium": 6.77 },        // derived, app units
  "portions": [ { "label": "1 can", "grams": 369.2, "ml": 355 } ]
}
```

- **Labels are stored as printed** (`label`: per-serving amounts, units and %DV), and `per_100g` is derived
  from them by the admin (`admin/shared/derive.mjs`). A reviewer sees both side by side.
- **Portions carry grams**, plus the mL or count wording they came from: "1 large egg" = 53 g, "1 can" = 369.2 g
  (355 mL), "1 slice" = 23 g (from "2 slices (46 g)").
- **Unknown stays unknown.** A label value of 0 is a declared zero; a missing value is absent. A nutrient printed
  only as a %DV stays unknown rather than being converted with an assumed reference.

### Preparation profiles

A product sold in one state and eaten in another has more than one profile on the same record (`as-sold`,
`prepared`, `drained`), one per label column. Cheerios' table, for example, has "cereal alone" and "with 125 mL
of 2% milk". There is no conversion between profiles; each comes from its own column. The app uses the default
profile (`as-sold` when present) for now; choosing a profile when logging comes later.

### A diary entry

Today an entry stores `quantity`, `unit` and a fallback `grams`, and its grams are recomputed from the food's
current servings. That already gives the behaviour provisional logging needs:

- **Weighed amounts never change.** An entry in g or oz stays that weight.
- **Portion amounts follow the record.** "1 pouch" follows the reviewed portion's grams.
- A provisional food logged by weight gets its nutrients when the record is published under the same id
  (`gtin:…`), or through an alias (`pending:…`).

Whether past entries should keep the numbers they were logged with after a later correction is still open (see
the README).
