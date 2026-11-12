# Record schema 3: one shape for every published food

Status: **agreed** 2026-11-12. This shape is the contract for every `record_revisions.data`, whoever writes it: the
CNF publish, the desktop digitise pipeline and the phone's label review. It is written down as JSON Schema in
`record.schema.json`, beside this file.

## Why

Four writers publish record data today, in four slightly different shapes:

| Writer | Where | `schema` | Records on prod |
|---|---|---|---|
| CNF publish (`server/cnf-publish.mjs`, admin) | `publish_official_records` | none | 5,993 |
| Digitise pipeline (`shared/publish-digitised.mjs`, admin) | `publish_digitised_records` | 2 | 12,506 |
| Phone label review (`buildRecord`, `mobile/lib/logic/label_reading.dart`) | `publish_device_review` | 2 | 0 |
| Desktop review (`buildPublish`, admin `shared/derive.mjs`) | `accept_extraction` | none | 0 |

They agree on the part the app reads: `name`, `brand`, `name_fr`, `default_profile`, `barcodes[].gtin`, and each
profile's `id`, `per_100g` and `portions[].label/grams` (`app_record_data`). Around that part they drift:

- **The same fact stored up to three times.** A digitised profile has `nutrients` (per serving), `per_100g` (derived
  from it) and `label` (as printed), plus `serving`, `serving_grams` and a serving portion that repeat each other.
- **`label` means two things.** On a digitised record it is `{ format, languages, claims }`; on its profiles it is
  the printed rows.
- **Fields go missing by writer.** The phone drops `percent_dv` and `ingredients.complete`; CNF portions labelled
  "250 ml" (11,516 of its 20,420) don't record the mL; densities are `density_g_per_ml`/`density_source` on CNF and
  `per_100g_basis` on digitised records.
- **Provenance has three shapes.** CNF's `source` names the dataset; a digitised `source` names the extraction; the
  phone's names the readers. None says how far the product was checked.

## The shape

A barcoded product (a real prod record, rewritten):

```jsonc
{
  "schema": 3,
  "name": "Dattes Medjoul",              // what it is called, without the brand
  "name_fr": null,
  "brand": "Kazidomi",                   // null for a generic food
  "descriptor": null,                    // what it is, when printed apart from the name: "sparkling water beverage"
  "qualifiers": [],                      // variant words printed on the package: "salted", "2%", "organic"
  "barcodes": [{ "gtin": "00000001000078", "raw": "00000178", "symbology": "upce" }],
  "package": { "text": "500g e", "amount": 500, "unit": "g", "count": null },
  "ingredients": { "text": "Medjoul Dates", "language": "en", "contains": null, "may_contain": null, "complete": true },
  "claims": [],                          // nutrition statements printed outside the table: "Source of fibre"
  "default_profile": "as-sold",
  "profiles": [
    {
      "id": "as-sold",
      "per_100g": { "energy": 315, "fat": 0, "satFat": 0, "carbs": 73, "sugars": 70, "fiber": 7.5, "protein": 2, "sodium": 12 },
      "portions": [
        { "label": "100 g", "grams": 100, "ml": null, "count": null, "grams_from": "label", "serving": true },
        { "label": "1 package", "grams": 500, "ml": null, "count": { "amount": 1, "unit": "package" }, "grams_from": "package", "serving": false }
      ],
      "density": null,
      "printed": {
        "format": "other",
        "languages": ["en"],
        "heading": null,
        "serving": { "text": "Nutritional Values for 100g:", "grams": 100, "ml": null, "count": null },
        "rows": [
          { "key": "energy", "amount": 315, "unit": "kcal", "percent_dv": null },
          { "key": "energy", "amount": 1335, "unit": "kJ", "percent_dv": null },
          { "key": "carbs", "amount": 73, "unit": "g", "percent_dv": null },
          { "key": "salt", "amount": 0.03, "unit": "g", "percent_dv": null }
          // … every row as printed
        ]
      }
    }
  ],
  "source": {
    "kind": "label",
    "method": "digitised",                // digitised | phone | desktop
    "review": "checks",                   // checks | model | person
    "version": "digitise-v1",
    "extraction": "42b4eb69-b2da-460a-9d8a-0336b580f29d",
    "attempt": 2,
    "readers": [{ "step": "transcribe", "provider": "anthropic", "model": "claude-haiku-5-5" }],
    "name_from": "label"                  // label | hint | descriptor
  }
}
```

A CNF food (`cnf:61`, rewritten):

```jsonc
{
  "schema": 3,
  "name": "Milk, fluid, partly skimmed, 2% M.F.",
  "name_fr": "Lait, partiellement écrémé, liquide, 2% M.G.",
  "brand": null, "descriptor": null, "qualifiers": [], "barcodes": [], "package": null, "ingredients": null, "claims": [],
  "default_profile": "as-sold",
  "profiles": [
    {
      "id": "as-sold",
      "per_100g": { "energy": 47, "protein": 3.31, "fat": 1.839, "carbs": 4.38 /* … 36 nutrients */ },
      "portions": [
        { "label": "250 ml", "grams": 257.8, "ml": 250, "count": null, "grams_from": "source", "serving": false },
        { "label": "100 ml", "grams": 103.1, "ml": 100, "count": null, "grams_from": "source", "serving": false }
      ],
      "density": { "g_per_ml": 1.031, "from": "source" },
      "printed": null
    }
  ],
  "source": {
    "kind": "cnf",
    "dataset": "Canadian Nutrient File 2026, Health Canada",
    "code": 61,
    "group": "Dairy and Egg Products",
    "attribution": "Contains information licensed under the Open Government Licence – Canada. Source: Canadian Nutrient File, Health Canada, 2026.",
    "licence_url": "https://open.canada.ca/en/open-government-licence-canada"
  }
}
```

## Fields

**Record.** Every field is always present; unknown is `null` (or `[]` for a list), never left out.

| Field | Type | Notes |
|---|---|---|
| `schema` | `3` | |
| `name` | string | Required, not blank. The product name without the brand. |
| `name_fr` | string \| null | |
| `brand` | string \| null | Null for a generic food. |
| `descriptor` | string \| null | |
| `qualifiers` | string[] | |
| `barcodes` | `{ gtin, raw, symbology }[]` | `gtin` is 14 digits with a valid check digit; `raw` and `symbology` may be null. |
| `package` | `{ text, amount, unit, count }` \| null | `amount` is the whole net quantity in `unit` (`g` or `ml`), null when the text can't be trusted; `count` is the units inside a multipack ("12 x 355 mL" → 4260 ml, count 12). |
| `ingredients` | `{ text, language, contains, may_contain, complete }` \| null | `language` is `en`, `fr` or `other`; `complete` is false when part of the list couldn't be read. |
| `claims` | string[] | |
| `default_profile` | string | The `id` of one of `profiles`. |
| `profiles` | Profile[] | At least one. |
| `source` | Source | |

**Profile.** One per label column (`as-sold`, `prepared`, `drained`), as `measurements.md` decided.

| Field | Type | Notes |
|---|---|---|
| `id` | `as-sold` \| `prepared` \| `drained` | Unique within the record. |
| `per_100g` | `{ [nutrient]: number }` | The app's nutrient keys and units (`mobile/lib/data/nutrients.dart`), 4 significant digits, ≥ 0. `energy` is required. A key that's absent is unknown; `0` is a declared zero. |
| `portions` | Portion[] | May be empty for a generic food (it's logged in g or oz). A product has its serving here. |
| `density` | `{ g_per_ml, from }` \| null | Required when a portion's grams come from mL (`grams_from: density`); given too when the label's serving prints both, and for CNF foods whose mL measures agree (liquids). `from`: `label` (the serving prints both g and mL), `source` (CNF's measures), `typical` (a typical density for the category). |
| `printed` | Printed \| null | The label column as printed. Null for CNF; required on a product. |

**Portion.**

| Field | Type | Notes |
|---|---|---|
| `label` | string | Short household words: "2 cookies (23 g)", "1 cookie", "1 package". Unique within the profile; never "g" or "oz" (the app adds those). |
| `grams` | number | Required, > 0, one decimal. A measure without grams isn't a portion. |
| `ml` | number \| null | |
| `count` | `{ amount, unit }` \| null | |
| `grams_from` | `label` \| `density` \| `package` \| `source` | Where the grams came from: printed grams, mL × `density`, the net quantity, or CNF. |
| `serving` | boolean | True on the one portion the printed column is per. |

**Printed.** Evidence, not arithmetic: copied from the label and never corrected.

| Field | Type | Notes |
|---|---|---|
| `format` | `canadian-current` \| `canadian-older` \| `us` \| `eu` \| `other` \| null | |
| `languages` | string[] | |
| `heading` | string \| null | The column heading, when the table has several. |
| `serving` | `{ text, grams, ml, count }` | The serving line as printed, and the numbers in it. |
| `rows` | `{ key, amount, unit, percent_dv }[]` | Every row with an amount or a %DV. `key` is a nutrient key or `salt`; `unit` may be `kJ`. |

**Source.** One of two shapes, by `kind`.

| `kind` | Fields |
|---|---|
| `cnf` | `dataset`, `code`, `group`, `attribution`, `licence_url` |
| `label` | `method` (`digitised`, `phone`, `desktop`); `review`; `version` (the reading's prompt version); `extraction` and `attempt` (where the readings are stored; the extraction is in dev for digitised products); `readers` (`{ step, provider, model }[]`); `name_from` (`label`, `hint`, `descriptor`) |

`review` says how far a label product was checked before it was published:

- `checks`: two independent reads, a verifier and the deterministic checks agreed, with nothing in dispute.
- `model`: something was disputed and a stronger model settled it from the photos.
- `person`: a person accepted it, on the phone or the desktop. The revision also links that review.

## Rules

1. **Nothing is stored twice.** Per-serving amounts are in `printed.rows`; the serving's grams are on the
   `serving: true` portion; how grams were reached is `grams_from` and `density`. Gone: `nutrients`,
   `serving_grams`, `per_100g_basis`, the profile's `serving` and `heading`, `density_g_per_ml` and `density_source`,
   the record's `label` and `label_format`, `name_source`.
2. **`per_100g` is the number everyone uses.** It's derived once, by the writer, from `printed` (or CNF), in the app's
   units. Readers never redo the arithmetic.
3. **A product carries its evidence; a generic carries its source.** `gtin:` and `food:` records have `printed` on
   every profile and a serving portion; `cnf:` records have neither.
4. **Grams for everything.** Every portion has grams. A mL-only label gets a density with its `from`, as
   `measurements.md` decided. When the serving prints both grams and mL, that is the density used for the label's
   other mL measures.
5. **One definition, checked in three places.** The shape is written once as JSON Schema
   (`docs/food-model/record.schema.json`). The admin's and the phone's tests validate their builders against it. A
   database function, `record_problems(data)`, rejects anything off-shape in all three publish functions, so nothing
   off-shape reaches a revision.

## From today's shapes

| Today | Schema 3 |
|---|---|
| profile `label` (rows) | `printed.rows` |
| profile `heading`, `serving` | `printed.heading`, `printed.serving` |
| profile `nutrients` (per serving) | dropped: `printed.rows` |
| `serving_grams` | the `serving: true` portion's `grams` |
| `per_100g_basis: label / ml-estimated` | portions' `grams_from`, plus `density` (`typical`) |
| `density_g_per_ml`, `density_source` | `density: { g_per_ml, from }` |
| record `label: { format, languages, claims }` | `printed.format`, `printed.languages`, record `claims` |
| `label_format` (desktop) | `printed.format` |
| `name_source: hint / descriptor` | `source.name_from` |
| CNF `source` | `source` with `kind: cnf` |
| digitised `source: { kind, version, extraction, attempt, model }` | `source` with `kind: label`, `method: digitised`, `review`, `readers` |
| phone `source: { kind: device-review, version, readers }` | `source` with `kind: label`, `method: phone`, `review: person` |
| CNF "250 ml" portions without mL | `ml: 250`, and the density they imply |

Every record today converts without new readings: the digitised ones from what each revision already holds (and the
extraction in dev, for `readers` and `review`); CNF from the bundled source.

## The app

The app reads records through `app_record_data`, and its paths don't change: `name`, `brand`, `name_fr`,
`default_profile`, `barcodes[].gtin`, `profiles[].id`, `profiles[].per_100g`, `profiles[].portions[].label` and
`grams`. Released apps (0.2.0 to 0.4.0) keep working on schema-3 records without an update.

The one writer in the app is the phone's label review. Version 0.4.0 publishes schema 2, and the next app version
writes schema 3. No phone review has been published on prod yet. If that version ships with the migration,
`publish_device_review` can require schema 3 from the start. Otherwise it accepts schema 2 until then.

## Rollout, then the end of the campaign

1. **Review.** The shape was agreed on 2026-11-12.
2. **Build.** The JSON Schema, `record_problems` and a migration that wires it into the three publish functions. The
   admin's CNF and digitised builders and the phone's `buildRecord` write schema 3, with tests.
3. **Republish everything** as schema 3: the 5,993 CNF foods and the 16,325 clear products, dev first, then staging,
   then prod with your go-ahead. Each record gets one new revision; nothing is overwritten, and a person-reviewed
   record is never touched. The app's next sync brings the changed records.
4. **End the campaign.** The Open Food Facts import, the digitise runner and the review runner are retired from the
   admin. The dev evidence stays (photos, readings, checks), and so do the 1,785 products for a person and the 2,733
   parked ones, unpublished. From then on, a product reaches the catalogue through the phone's label review.

## Decided

- **The 1,785 for a person and the 2,733 parked** stay unpublished and are set aside for now (2026-11-12). A scan of
  one goes through the phone like any new product.
- **French names:** `name_fr` stays beside `name`, as the app reads it today.
- **Still open:** whether the desktop review queue retires with the campaign. Two app submissions have waited in
  prod's queue since 2026-10-24/25. `accept_extraction` (the desktop accept) still publishes the old shape and isn't
  checked by `record_problems`; it would need moving to schema 3 if the queue stays.
