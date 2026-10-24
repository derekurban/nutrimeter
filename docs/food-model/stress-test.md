# Food model stress test

> **Later decisions (2026-10-23):** Open Food Facts has since been dropped as a data source, so the findings about OFF reliability (P0.4 and the OFF-specific parts of other gaps) now apply to our own photo extraction instead. Gaps P0.1, P0.2, P0.3, P1.1, P1.2 and P1.7 are folded into `README.md` and `measurements.md`. This report was written by gpt-6.1-sol against the earlier draft and is otherwise unchanged.

Review date: 2026-10-23. This tests the draft as written, not an implemented catalogue. Only this report is changed. Evidence: [model](README.md), [frozen OFF extracts](candidates.json), `mobile/assets/cnf/foods.json`, the current Food/OFF/CNF clients and `data/cnf/README.md`. No live OFF queries were made.

**Verdicts: 3 fits; 8 fits with a rule; 9 breaks.** A break is a missing shape or contradictory mandatory behaviour, not merely a bad source value. A rule verdict needs explicit validation, selection or display policy; it does not imply the source is verified.

The top gaps are (1) nutrition and portions need typed mass/volume bases, (2) preparation needs multiple profiles under a product, (3) defaults must be nullable and distinguish generic from branded references, (4) concept-only titles conceal meaningful variants, and (5) barcode identity needs symbology-aware canonicalisation. Evidence quality and diary revision semantics are also release blockers.

**Count: 18 attached food/form identities plus 8 food parents = 26 food/form concepts, with 18 distinct unbranded images.** Ten section nodes make 36 total tree nodes if sections are also stored as concepts. This is a concrete proposed minimal catalogue, not a uniquely implied answer: the draft leaves granularity ambiguous. It includes only the twenty products’ paths and selected defaults, not every alternative CNF form. Prepared oatmeal, drained chickpeas and prepared macaroni would add concepts/images when actually included. All selected defaults except the three missing ones share their product’s concept.

## Reading the numerical evidence

The extracts are structured OFF assertions, **not photographs of printed labels**. They retain only energy, protein, fat and carbohydrate per serving for most products. Every section quotes the exact supplied serving string and all explicit per-serving assertions. Other values are listed on their supplied 100-unit basis and, separately, reverse-scaled for inspection. Reverse-scaled numbers are not an authenticated printed label and must not be stored as one. `nutrientsKnownPer100g` counts more fields than the extract actually contains; it cannot recover missing vitamins or minerals.

Energy is kcal; P/F/C are protein/fat/carbohydrate in g. Other nutrients are g except sodium in mg. OFF sodium in g is multiplied by 1000 for this table; suspect values remain visible as evidence, not accepted corrections. Unknown is **—**, never zero. OFF `energy_100g` is retained separately as an unverified kJ assertion; inconsistent kcal/kJ pairs require label review rather than 4/4/9 recomputation. Derived figures below are rounded to three decimals for reading; retain source precision internally.

For consistent gram-based sources, derived 100 g values use the explicit per-serving value × 100 / serving grams. Nutrients lacking a per-serving assertion retain the source 100 g assertion and are labelled as such. A volume-only product has **no derived per-100 g values** without its own supported density. Per-100 mL is a valid basis, not a missing gram value to guess. #9 and #12 are explicitly unresolved.

IDs below propose canonical **GTIN-14** strings. All nineteen supplied 13-digit identifiers pass their check digit and gain one leading zero. Barcode representations remain strings. #15 is expanded before padding. Preserve the old `off:<raw>` IDs as aliases if migrating the current app; retain raw codes for OFF lookup because canonical storage need not equal an upstream lookup key. These are proposed record keys, not newly minted production records.

The row shown in each section is the literal concept-title/brand rule, followed by the record’s selected serving and energy. Missing/ambiguous basis must be visible. CNF default rows use the same concept title and “Generic” **except where this report calls that false**. Scans below describe the catalogue after review; before that, the documented provisional `concept:null` path must display the supplied provisional name without an image until attachment.

## Product walkthroughs

### 1. Organic Eggs — Kirkland Signature

**Concept:** `egg-whole-raw` — Egg, whole, raw. Path: **Eggs → `egg` → `egg-whole-raw`. New attachment concept, seedable from the selected CNF row. Inherits parent `egg` image; the parent owns the asset `egg-whole-raw`.

**Default:** `cnf:125`. **Verdict: fits with a rule.** Use cnf:125: whole raw edible egg, not fried 129 or boiled 130. Organic and large are record attributes; size is a serving, not a concept. Package 1272 g equals 24 × 53 g but edible versus shell-inclusive mass needs confirmation; do not offer shell weight as edible grams. The example display “Egg, large” conflicts with concept-only naming; show size in the serving. Searching egg must rank this raw form ahead of cooked children.

**Record:** `gtin:00096619845774`; raw scan `0096619845774` → GTIN-14 `00096619845774`. Supplied serving string: **“1 large egg (53 g)”**; quantity field `53 g`; nutrition basis `100g`.

| Nutrient | Explicit OFF per serving | Source per 100 g | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 70 | 132.075 | 132.075 | 70 |
| Protein (g) | 6 | 11.321 | 11.321 | 6 |
| Fat (g) | 5 | 9.434 | 9.434 | 5 |
| Saturated fat (g) | — | 2.83 | — | 1.5 |
| Carbohydrate (g) | 1 | 1.887 | 1.887 | 1 |
| Sugars (g) | — | 0 | — | 0 |
| Fibre (g) | — | 0 | — | 0 |
| Sodium (mg) | — | 122.642 | — | 65 |

For nutrients without explicit per-serving values, the source per-100 g column is the available record assertion; no new precision is claimed.

Additional OFF energy assertion: `573.585 kJ/100 g` (unit interpretation follows the declared basis). Preserve independently and verify against kcal.

**Record servings:** 1 egg = 53 g; 24-egg package = 1272 g only if edible mass is confirmed. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Egg, whole, raw · Kirkland Signature** — “1 large egg (53 g)”, 70 kcal. The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“egg”**: generic words should yield concept `egg-whole-raw` → `cnf:125`. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0096619845774` → `gtin:00096619845774` → `egg-whole-raw` → this record’s own nutrition and servings.

### 2. Partly Skimmed Milk — Dairyland

**Concept:** `milk` — Milk. Path: **Dairy → `milk`. New attachment concept, seedable from the selected CNF row. Own shared image asset `milk`.

**Default:** `cnf:61`. **Verdict: breaks.** cnf:61 is the sensible 2% reference, but choosing 2% as the broad milk default is a judgement call. The category tags contradict one another (semi-skimmed and skimmed). A cup is explicitly 240 mL here, not the CNF 250 mL measure. The label values are per volume; no product density is supplied. The model cannot truthfully fill its mandatory per100g or gram servings. Add typed volume quantities and a 2% record qualifier; do not turn 4000 mL into 4000 g.

**Record:** `gtin:00068700011016`; raw scan `0068700011016` → GTIN-14 `00068700011016`. Supplied serving string: **“1 portion (1 cup)”**; quantity field `240 ml`; nutrition basis `100ml`.

| Nutrient | Explicit OFF per serving | Source per 100 mL | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 130 | 54.167 | — | 130 |
| Protein (g) | 9 | 3.75 | — | 9 |
| Fat (g) | 5 | 2.083 | — | 5 |
| Saturated fat (g) | — | 1.25 | — | 3 |
| Carbohydrate (g) | 12 | 5 | — | 12 |
| Sugars (g) | — | 5 | — | 12 |
| Fibre (g) | — | 0 | — | 0 |
| Sodium (mg) | — | 50 | — | 120 |

All reverse-scaled servings here are volume calculations. Derived per-100 g is unknown for every nutrient; gram logging must be unavailable until density is supported.

Additional OFF energy assertion: `225.833 kJ/100 mL` (unit interpretation follows the declared basis). Preserve independently and verify against kcal.

**Record servings:** 1 portion (1 cup) (240 ml); package = 4000 ml. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Milk · Dairyland** — “1 portion (1 cup)”, 130 kcal. The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“milk”**: generic words should yield concept `milk` → `cnf:61`. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0068700011016` → `gtin:00068700011016` → `milk` → this record’s own nutrition and servings.

### 3. Oikos Yogourt Grec Nature — Danone, Oikos

**Concept:** `yogurt-greek-plain` — Greek yogurt, plain. Path: **Dairy → `yogurt` → `yogurt-greek-plain`. New attachment concept, seedable from the selected CNF row. Inherits parent `yogurt` image; the parent owns the asset `yogurt-greek-plain`.

**Default:** `cnf:6979`. **Verdict: fits with a rule.** Choose cnf:6979, fat-free plain Greek yogurt, because this product has skim milk and zero declared fat; reject 7469 for this product. For the visually shared concept, fat-free as the default is a judgement call, not a conclusion about every Greek yogurt. A 2% version belongs to the same concept under the stated granularity rule. Show record qualifiers “0%” and “2%” and index them. Do not inherit CNF volume measures into this 175 g label.

**Record:** `gtin:00056800664812`; raw scan `0056800664812` → GTIN-14 `00056800664812`. Supplied serving string: **“175 g”**; quantity field `175 g`; nutrition basis `100g`.

| Nutrient | Explicit OFF per serving | Source per 100 g | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 100 | 57.143 | 57.143 | 100 |
| Protein (g) | 17 | 9.714 | 9.714 | 17 |
| Fat (g) | 0 | 0 | 0 | 0 |
| Saturated fat (g) | — | 0 | — | 0 |
| Carbohydrate (g) | 8 | 4.571 | 4.571 | 8 |
| Sugars (g) | — | 2.286 | — | 4 |
| Fibre (g) | — | 0 | — | 0 |
| Sodium (mg) | — | 34.286 | — | 60 |

For nutrients without explicit per-serving values, the source per-100 g column is the available record assertion; no new precision is claimed.

Additional OFF energy assertion: `242.857 kJ/100 g` (unit interpretation follows the declared basis). Preserve independently and verify against kcal.

**Record servings:** 175 g (175 g); package = 500 g. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Greek yogurt, plain · Oikos** — “175 g”, 100 kcal. The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“Greek yogurt”**: generic words should yield concept `yogurt-greek-plain` → `cnf:6979`. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0056800664812` → `gtin:00056800664812` → `yogurt-greek-plain` → this record’s own nutrition and servings.

### 4. Smooth Peanut Butter — Kraft

**Concept:** `peanut-butter-smooth` — Peanut butter, smooth. Path: **Nuts and seeds → `peanut-butter` → `peanut-butter-smooth`. New attachment concept, seedable from the selected CNF row. Inherits parent `peanut-butter` image; the parent owns the asset `peanut-butter-smooth`.

**Default:** `cnf:3399`. **Verdict: fits with a rule.** cnf:3399 includes added oil, sugar and salt, matching the ingredients; 3414 omits added salt. This is a conventional sweetened smooth reference, a judgement call for the wider smooth concept. OFF protein = 0 is implausible for a peanut-based spread. Preserve that assertion in raw evidence but mark protein disputed/unknown in the accepted record until a label photo resolves it; never replace it with CNF protein. “Nutrition completed” cannot be a publication test. Serving says 15 g, not a verified tablespoon.

**Record:** `gtin:00068100084276`; raw scan `0068100084276` → GTIN-14 `00068100084276`. Supplied serving string: **“1 serving (15 g)”**; quantity field `15 g`; nutrition basis `100g`.

| Nutrient | Explicit OFF per serving | Source per 100 g | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 90 | 600 | 600 | 90 |
| Protein (g) | 0 | 0 | 0 | 0 |
| Fat (g) | 8 | 53.333 | 53.333 | 8 |
| Saturated fat (g) | — | 10 | — | 1.5 |
| Carbohydrate (g) | 4 | 26.667 | 26.667 | 4 |
| Sugars (g) | — | 6.667 | — | 1 |
| Fibre (g) | — | 6.667 | — | 1 |
| Sodium (mg) | — | 400 | — | 60 |

For nutrients without explicit per-serving values, the source per-100 g column is the available record assertion; no new precision is claimed.

Additional OFF energy assertion: `2480 kJ/100 g` (unit interpretation follows the declared basis). Preserve independently and verify against kcal.

**Record servings:** 1 serving (15 g) (15 g); package = 2000 g. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Peanut butter, smooth · Kraft** — “1 serving (15 g)”, 90 kcal. The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“peanut butter”**: generic words should yield concept `peanut-butter-smooth` → `cnf:3399`. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0068100084276` → `gtin:00068100084276` → `peanut-butter-smooth` → this record’s own nutrition and servings.

### 5. Large Flake Oats — Quaker

**Concept:** `oats-rolled-dry` — Rolled oats, dry. Path: **Cereals and grains → `oats` → `oats-rolled-dry`. New attachment concept, seedable from the selected CNF row. Inherits parent `oats` image; the parent owns the asset `oats-rolled-dry`.

**Default:** `cnf:1464`. **Verdict: breaks.** cnf:1464 is the closest large-flake dry reference but explicitly Quaker; 1462 is Rogers and 6276 in the asset is Cream Hill Estates. Neither is generic. cnf:4421 is brandless “Grains, oats, dry”, but its 250 mL mass is 164.8 g versus 110.9 g for Rogers large flakes: do not silently substitute a different physical form. Choose 1464 only as a branded reference with a default-role label; the literal display rule incorrectly calls it Generic. 1465 is prepared oatmeal and must not share this dry default. OFF 112 kcal/30 g derives to 373.333, not its 375/100 g; preserve both assertions pending label review. Do not silently choose or round one into the other.

**Record:** `gtin:00055577101018`; raw scan `0055577101018` → GTIN-14 `00055577101018`. Supplied serving string: **“30 g”**; quantity field `30 g`; nutrition basis `100g`.

| Nutrient | Explicit OFF per serving | Source per 100 g | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 112 | 375 | 373.333 | 112.5 |
| Protein (g) | 4 | 13.333 | 13.333 | 4 |
| Fat (g) | 2 | 6.667 | 6.667 | 2 |
| Saturated fat (g) | — | 1.333 | — | 0.4 |
| Carbohydrate (g) | 20 | 66.667 | 66.667 | 20 |
| Sugars (g) | — | 0 | — | 0 |
| Fibre (g) | — | 10 | — | 3 |
| Sodium (mg) | — | 3.333 | — | 1 |

For nutrients without explicit per-serving values, the source per-100 g column is the available record assertion; no new precision is claimed.

Additional OFF energy assertion: `1686.667 kJ/100 g` (unit interpretation follows the declared basis). Preserve independently and verify against kcal.

**Record servings:** 30 g (30 g); package = 1000 g. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Rolled oats, dry · Quaker** — “30 g”, 112 kcal. The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“oats”**: generic words should yield concept `oats-rolled-dry` → `cnf:1464`. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0055577101018` → `gtin:00055577101018` → `oats-rolled-dry` → this record’s own nutrition and servings.

### 6. Chick peas — Great Value Canada

**Concept:** `chickpeas-canned` — Chickpeas, canned. Path: **Legumes → `chickpeas` → `chickpeas-canned`. New attachment concept, seedable from the selected CNF row. Inherits parent `chickpeas` image; the parent owns the asset `chickpeas-canned`.

**Default:** `cnf:3279`. **Verdict: breaks.** Tentatively choose cnf:3279, solids and liquid, as this concept default. It is a judgement call, not an established interpretation of this can. cnf:7060 is drained, and 7242 is reduced-sodium solids and liquid; lower product sodium alone does not establish either state. A volume serving does not establish drained state. The label must say what the 125 mL contains. Add a measured-state field and separate drained versus undrained nutrition profiles; a user draining the can cannot use these numbers by inference. Neither 540 mL nor 125 mL has a product-specific gram equivalent.

**Record:** `gtin:00681131861410`; raw scan `0681131861410` → GTIN-14 `00681131861410`. Supplied serving string: **“1 portion (125 ml)”**; quantity field `125 ml`; nutrition basis `100ml`.

| Nutrient | Explicit OFF per serving | Source per 100 mL | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 100 | 80 | — | 100 |
| Protein (g) | 6 | 4.8 | — | 6 |
| Fat (g) | 2 | 1.6 | — | 2 |
| Saturated fat (g) | — | 0.24 | — | 0.3 |
| Carbohydrate (g) | 18 | 14.4 | — | 18 |
| Sugars (g) | — | — | — | — |
| Fibre (g) | — | 4 | — | 5 |
| Sodium (mg) | — | 112 | — | 140 |

All reverse-scaled servings here are volume calculations. Derived per-100 g is unknown for every nutrient; gram logging must be unavailable until density is supported.

Additional OFF energy assertion: `417.6 kJ/100 mL` (unit interpretation follows the declared basis). Preserve independently and verify against kcal.

**Record servings:** 1 portion (125 ml) (125 ml); package = 540 ml. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Chickpeas, canned · Great Value Canada** — “1 portion (125 ml)”, 100 kcal. The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“chickpeas”**: generic words should yield concept `chickpeas-canned` → `cnf:3279`. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0681131861410` → `gtin:00681131861410` → `chickpeas-canned` → this record’s own nutrition and servings.

### 7. Chocolate Sandwich Cookies — Oreo

**Concept:** `chocolate-sandwich-cookie` — Chocolate sandwich cookie. Path: **Snacks → `chocolate-sandwich-cookie`. New attachment concept, seedable from the selected CNF row. Own shared image asset `chocolate-sandwich-cookie`.

**Default:** `cnf:3819`. **Verdict: fits.** cnf:3819 explicitly covers chocolate sandwich cookies with chocolate or vanilla filling. This is the first product attached; the CNF row can seed the concept. Keep the 3-cookie/34 g label and derive 1 cookie = 34/3 g, not the CNF 12 g. The 270 g package is separate from a serving. No structural addition is needed for this product.

**Record:** `gtin:00066721026590`; raw scan `0066721026590` → GTIN-14 `00066721026590`. Supplied serving string: **“3 cookies (34 g)”**; quantity field `34 g`; nutrition basis `100g`.

| Nutrient | Explicit OFF per serving | Source per 100 g | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 160 | 470.588 | 470.588 | 160 |
| Protein (g) | 1 | 2.941 | 2.941 | 1 |
| Fat (g) | 7 | 20.588 | 20.588 | 7 |
| Saturated fat (g) | — | 5.882 | — | 2 |
| Carbohydrate (g) | 25 | 73.529 | 73.529 | 25 |
| Sugars (g) | — | 41.176 | — | 14 |
| Fibre (g) | — | 2.941 | — | 1 |
| Sodium (mg) | — | 323.529 | — | 110 |

For nutrients without explicit per-serving values, the source per-100 g column is the available record assertion; no new precision is claimed.

Additional OFF energy assertion: `2085.294 kJ/100 g` (unit interpretation follows the declared basis). Preserve independently and verify against kcal.

**Record servings:** 3 cookies = 34 g; derived 1 cookie = 11.333… g; package = 270 g. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Chocolate sandwich cookie · Oreo** — “3 cookies (34 g)”, 160 kcal. The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“cookie / Oreo”**: generic words should yield concept `chocolate-sandwich-cookie` → `cnf:3819`. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0066721026590` → `gtin:00066721026590` → `chocolate-sandwich-cookie` → this record’s own nutrition and servings.

### 8. Chocolate Vanilla Flavour Cookies — Biskwi

**Concept:** `chocolate-sandwich-cookie` — Chocolate sandwich cookie. Path: **Snacks → `chocolate-sandwich-cookie`. Already created by #7. Own shared image asset `chocolate-sandwich-cookie`. Reuses the existing image; no new image.

**Default:** `cnf:3819`. **Verdict: fits with a rule.** Reuse #7 and cnf:3819; categories support a chocolate sandwich cookie with vanilla filling. Do not create a Biskwi concept or image. A 35 g serving supplies no cookie count. Record servings must replace, not union with, concept servings when their weights are not verified for this record: importing the CNF 12 g cookie would invent accuracy. A label photo is needed before offering a cookie unit.

**Record:** `gtin:00667888380534`; raw scan `0667888380534` → GTIN-14 `00667888380534`. Supplied serving string: **“35 g”**; quantity field `35 g`; nutrition basis `100g`.

| Nutrient | Explicit OFF per serving | Source per 100 g | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 170 | 485.714 | 485.714 | 170 |
| Protein (g) | 2 | 5.714 | 5.714 | 2 |
| Fat (g) | 7 | 20 | 20 | 7 |
| Saturated fat (g) | — | 8.571 | — | 3 |
| Carbohydrate (g) | 24 | 68.571 | 68.571 | 24 |
| Sugars (g) | — | 37.143 | — | 13 |
| Fibre (g) | — | 0 | — | 0 |
| Sodium (mg) | — | 328.571 | — | 115 |

For nutrients without explicit per-serving values, the source per-100 g column is the available record assertion; no new precision is claimed.

Additional OFF energy assertion: `2002.857 kJ/100 g` (unit interpretation follows the declared basis). Preserve independently and verify against kcal.

**Record servings:** 35 g; package = 300 g; no verified cookie count. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Chocolate sandwich cookie · Biskwi** — “35 g”, 170 kcal. The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“cookie / Biskwi”**: generic words should yield concept `chocolate-sandwich-cookie` → `cnf:3819`. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0667888380534` → `gtin:00667888380534` → `chocolate-sandwich-cookie` → this record’s own nutrition and servings.

### 9. Oat Original — Earth's Own

**Concept:** `oat-drink` — Oat drink. Path: **Drinks → `oat-drink`. New concept; no suitable CNF seed. Own shared image asset `oat-drink`.

**Default:** **none**. **Verdict: breaks.** Reject cnf:7808: it is an unsweetened oat-and-quinoa blend, not this oat-only Original drink. The asset search found no oat-only beverage alternative. Default must be null until a suitable researched generic exists; the schema/resolver must explicitly support this. OFF says per 100 mL but serving unit g (250 g); this is a contradiction, not evidence that density is 1. Quarantine the basis pending label review. Search oat milk/oat drink should find this concept and offer an explicit product choice or an unavailable generic, not silently select Earth’s Own or the quinoa blend.

**Record:** `gtin:00626027811025`; raw scan `0626027811025` → GTIN-14 `00626027811025`. Supplied serving string: **“1 serving (250 g)”**; quantity field `250 g`; nutrition basis `100ml`.

| Nutrient | Explicit OFF per serving | Source per 100 mL | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 125 | 50 | — | 125 |
| Protein (g) | 3 | 1.2 | — | 3 |
| Fat (g) | 5 | 2 | — | 5 |
| Saturated fat (g) | — | 0.2 | — | 0.5 |
| Carbohydrate (g) | 17 | 6.8 | — | 17 |
| Sugars (g) | — | 2.8 | — | 7 |
| Fibre (g) | — | 0.8 | — | 2 |
| Sodium (mg) | — | 48 | — | 120 |

The reverse scaling only shows arithmetic consistency with the numerical serving quantity. It does not resolve the contradictory unit/preparation claim, so it supplies no accepted per-100 g profile.

Additional OFF energy assertion: `216.4 kJ/100 mL` (unit interpretation follows the declared basis). Preserve independently and verify against kcal.

**Record servings:** 1 serving (250 g) (250 g); package = 1750.0 ml; 250 g versus per-100 mL basis unresolved; do not convert package volume to mass. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Oat drink · Earth's Own** — “1 serving (250 g)”, 125 kcal (basis unresolved; provisional). The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“oat milk”**: generic words should yield concept `oat-drink` → **no default**; the draft has no defined successful result. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0626027811025` → `gtin:00626027811025` → `oat-drink` → this record’s own nutrition and servings (keep provisional until the basis is resolved).

### 10. Chewy Protein Bar — Kirkland

**Concept:** `protein-bar` — Protein bar. Path: **Snacks → `protein-bar`. New concept; no suitable CNF seed. Own shared image asset `protein-bar`.

**Default:** **none**. **Verdict: breaks.** No sensible CNF match is supplied. A broad protein-bar concept can share an unbranded bar image, but no representative nutrition default follows from shape. Keep default null; a researched generic would be a new record, not invented CNF data. The literal search-to-default path cannot serve protein bar. Quantity “Kirkland” is junk and product mass is null: offer only 1 bar = 40 g, never a package. Ingredients are truncated at “Gly”; do not infer allergens or composition completeness. Product flavour/variant must remain visible when the brand sells multiple bars.

**Record:** `gtin:00096619796274`; raw scan `0096619796274` → GTIN-14 `00096619796274`. Supplied serving string: **“1 bar (40 g)”**; quantity field `40 g`; nutrition basis `100g`.

| Nutrient | Explicit OFF per serving | Source per 100 g | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 180 | 450 | 450 | 180 |
| Protein (g) | 10 | 25 | 25 | 10 |
| Fat (g) | 11 | 27.5 | 27.5 | 11 |
| Saturated fat (g) | — | 7.5 | — | 3 |
| Carbohydrate (g) | 16 | 40 | 40 | 16 |
| Sugars (g) | — | 15 | — | 6 |
| Fibre (g) | — | 15 | — | 6 |
| Sodium (mg) | — | 312.5 | — | 125 |

For nutrients without explicit per-serving values, the source per-100 g column is the available record assertion; no new precision is claimed.

Additional OFF energy assertion: `2242.5 kJ/100 g` (unit interpretation follows the declared basis). Preserve independently and verify against kcal.

**Record servings:** 1 bar = 40 g; package unknown. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Protein bar · Kirkland** — “1 bar (40 g)”, 180 kcal. The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“protein bar”**: generic words should yield concept `protein-bar` → **no default**; the draft has no defined successful result. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0096619796274` → `gtin:00096619796274` → `protein-bar` → this record’s own nutrition and servings.

### 11. Pulled Chicken Burrito Bowl — CRAVE

**Concept:** `chicken-burrito-bowl` — Chicken burrito bowl. Path: **Meals → `chicken-burrito-bowl`. New concept; no suitable CNF seed. Own shared image asset `chicken-burrito-bowl`.

**Default:** **none**. **Verdict: breaks.** No CNF default. This is one composite concept and one unbranded bowl illustration, as decided; do not split out chicken, rice and beans. Search burrito bowl needs a no-default path. A generic-looking title plus CRAVE hides “Pulled Chicken” if the concept is later broadened; retain product variant text. For this narrow concept it fits the identity, but the missing default still breaks resolution. 1 package = 320 g is also the serving; store one quantity with two labels, not two independent conversions.

**Record:** `gtin:00057000010805`; raw scan `0057000010805` → GTIN-14 `00057000010805`. Supplied serving string: **“1 package (320 g)”**; quantity field `320 g`; nutrition basis `100g`.

| Nutrient | Explicit OFF per serving | Source per 100 g | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 410 | 128.125 | 128.125 | 410 |
| Protein (g) | 29 | 9.062 | 9.062 | 29 |
| Fat (g) | 15 | 4.688 | 4.688 | 15 |
| Saturated fat (g) | — | 2.5 | — | 8 |
| Carbohydrate (g) | 42 | 13.125 | 13.125 | 42 |
| Sugars (g) | — | 1.875 | — | 6 |
| Fibre (g) | — | 0.625 | — | 2 |
| Sodium (mg) | — | 371.875 | — | 1190 |

For nutrients without explicit per-serving values, the source per-100 g column is the available record assertion; no new precision is claimed.

Additional OFF energy assertion: `555.625 kJ/100 g` (unit interpretation follows the declared basis). Preserve independently and verify against kcal.

**Record servings:** 1 package/serving = 320 g. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Chicken burrito bowl · CRAVE** — “1 package (320 g)”, 410 kcal. The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“burrito bowl”**: generic words should yield concept `chicken-burrito-bowl` → **no default**; the draft has no defined successful result. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0057000010805` → `gtin:00057000010805` → `chicken-burrito-bowl` → this record’s own nutrition and servings.

### 12. Macaroni and Cheese — KD Original

**Concept:** `macaroni-cheese-box-dry` — Macaroni and cheese, box mix, dry. Path: **Meals → `macaroni-cheese` → `macaroni-cheese-box-dry`. New attachment concept, seedable from the selected CNF row. Inherits parent `macaroni-cheese` image; the parent owns the asset `macaroni-cheese-box-dry`.

**Default:** `cnf:7140`. **Verdict: breaks.** Tentatively attach the sold product to the dry form and choose cnf:7140, unprepared box mix with cheese sauce, as the closest reference, not an exact powder-sauce match. cnf:7141 belongs to a separate prepared form. OFF marks all supplied nutrition prepared, yet 360 kcal per 85 g looks like a dry amount. Do not relabel it as dry by plausibility or use prepared numbers against the 200 g dry box. Keep the imported prepared profile unresolved and non-publishable until the label establishes basis, additions and yield. One GTIN needs multiple named nutrition profiles, each with servings and state; a single concept pointer plus flat per100g cannot express both dry and prepared safely. The 200 g package is known only as sold.

**Record:** `gtin:00068100904826`; raw scan `0068100904826` → GTIN-14 `00068100904826`. Supplied serving string: **“85g”**; quantity field `85 g`; nutrition basis `serving`; prepared flag `on`.

| Nutrient | Explicit OFF per serving | Source per 100 g (prepared claim) | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 360 | 423.529 | — | 360 |
| Protein (g) | — | 12.941 | — | 11 |
| Fat (g) | — | 2.941 | — | 2.5 |
| Saturated fat (g) | — | — | — | — |
| Carbohydrate (g) | — | 71.765 | — | 61 |
| Sugars (g) | — | 12.941 | — | 11 |
| Fibre (g) | — | 2.353 | — | 2 |
| Sodium (mg) | — | 658.824 | — | 560 |

The reverse scaling only shows arithmetic consistency with the numerical serving quantity. It does not resolve the contradictory unit/preparation claim, so it supplies no accepted per-100 g profile.

**Record servings:** 85 g, preparation basis unresolved; dry package = 200 g; do not apply profile to package. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Macaroni and cheese, box mix, dry · KD Original** — “85g”, 360 kcal (basis unresolved; provisional). The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“Kraft Dinner / macaroni and cheese”**: generic words should yield concept `macaroni-cheese-box-dry` → `cnf:7140`. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0068100904826` → `gtin:00068100904826` → `macaroni-cheese-box-dry` → this record’s own nutrition and servings (keep provisional until the basis is resolved).

### 13. HAZELNUT SPREAD WITH COCOA — Ferrero Rocher, Nutella

**Concept:** `cocoa-hazelnut-spread` — Cocoa hazelnut spread. Path: **Spreads and dips → `cocoa-hazelnut-spread`. New attachment concept, seedable from the selected CNF row. Own shared image asset `cocoa-hazelnut-spread`.

**Default:** `cnf:5736`. **Verdict: fits with a rule.** cnf:5736 is a direct generic match. The brand string “Ferrero Rocher, Nutella” is not a reliable preferred-brand ordering; curate Nutella as display brand and retain both search aliases. Total carbohydrate is absent: do not derive it from sugar or energy. Sodium 52.6316 g/100 g is impossible alongside the other supplied mass values and appears to be an mg-as-g mistake. A plausible 10 mg per 19 g is a hypothesis, not a corrected label. Preserve raw sodium and leave accepted sodium unknown pending photo. The concept shape works with evidence validation.

**Record:** `gtin:00062020000842`; raw scan `0062020000842` → GTIN-14 `00062020000842`. Supplied serving string: **“19 g”**; quantity field `19 g`; nutrition basis `100g`.

| Nutrient | Explicit OFF per serving | Source per 100 g | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 110 | 578.947 | 578.947 | 110 |
| Protein (g) | 1 | 5.263 | 5.263 | 1 |
| Fat (g) | 6 | 31.579 | 31.579 | 6 |
| Saturated fat (g) | — | 10.526 | — | 2 |
| Carbohydrate (g) | — | — | — | — |
| Sugars (g) | — | 63.158 | — | 12 |
| Fibre (g) | — | 5.263 | — | 1 |
| Sodium (mg) | — | 52631.579 | — | 10000 |

For nutrients without explicit per-serving values, the source per-100 g column is the available record assertion; no new precision is claimed.

**Record servings:** 19 g (19 g); package = 725 g. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Cocoa hazelnut spread · Nutella** — “19 g”, 110 kcal. The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“Nutella / hazelnut spread”**: generic words should yield concept `cocoa-hazelnut-spread` → `cnf:5736`. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0062020000842` → `gtin:00062020000842` → `cocoa-hazelnut-spread` → this record’s own nutrition and servings.

### 14. Hazelnut Spread with Cocoa — Kirkland Signature

**Concept:** `cocoa-hazelnut-spread` — Cocoa hazelnut spread. Path: **Spreads and dips → `cocoa-hazelnut-spread`. Already created by #13. Own shared image asset `cocoa-hazelnut-spread`. Reuses the existing image; no new image.

**Default:** `cnf:5736`. **Verdict: fits.** Reuse #13 and cnf:5736. Rapeseed rather than palm oil is record composition, not a new picture or concept. Keep the printed French tablespoon label and its explicit 20 g; it is not CNF’s 18.75 g per 15 mL. Ingredient text is damaged, so retain it as raw evidence and do not claim a clean ingredient transcription. The supplied nutrition and gram basis fit.

**Record:** `gtin:00096619331130`; raw scan `0096619331130` → GTIN-14 `00096619331130`. Supplied serving string: **“1 c. à soupe (20 g)”**; quantity field `20 g`; nutrition basis `100g`.

| Nutrient | Explicit OFF per serving | Source per 100 g | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 110 | 550 | 550 | 110 |
| Protein (g) | 1 | 5 | 5 | 1 |
| Fat (g) | 6 | 30 | 30 | 6 |
| Saturated fat (g) | — | 5 | — | 1 |
| Carbohydrate (g) | 11 | 55 | 55 | 11 |
| Sugars (g) | — | 50 | — | 10 |
| Fibre (g) | — | 5 | — | 1 |
| Sodium (mg) | — | 50 | — | 10 |

For nutrients without explicit per-serving values, the source per-100 g column is the available record assertion; no new precision is claimed.

Additional OFF energy assertion: `2170 kJ/100 g` (unit interpretation follows the declared basis). Preserve independently and verify against kcal.

**Record servings:** 1 c. à soupe (20 g) (20 g); package = 1000 g. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Cocoa hazelnut spread · Kirkland Signature** — “1 c. à soupe (20 g)”, 110 kcal. The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“hazelnut spread / Kirkland hazelnut”**: generic words should yield concept `cocoa-hazelnut-spread` → `cnf:5736`. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0096619331130` → `gtin:00096619331130` → `cocoa-hazelnut-spread` → this record’s own nutrition and servings.

### 15. Coca-Cola Original Taste — Coca-Cola

**Concept:** `cola` — Cola. Path: **Drinks → `cola`. New attachment concept, seedable from the selected CNF row. Own shared image asset `cola`.

**Default:** `cnf:5288`. **Verdict: breaks.** cnf:5288 is the generic regular sugared cola reference, not diet cola. 06782900 is identified by the candidate brief as UPC-E: expand it to UPC-A 067000008290, then canonical GTIN-14 00067000008290. Merely padding the eight digits gives a different identity. Its checksum alone does not identify UPC-E versus EAN-8: both happen to validate here. Store scanner symbology and raw code; ambiguous eight-digit text requires confirmation/lookup evidence. Label values are per mL, not per g; CNF 355 mL = 370.2 g illustrates why equating them is wrong but is not this product’s measured density. Caffeine is an ingredient, but its amount is absent; show —.

**Record:** `gtin:00067000008290`; raw scan `06782900` → UPC-A `067000008290` → GTIN-14 `00067000008290`. Supplied serving string: **“1 serving (355 ml)”**; quantity field `355 ml`; nutrition basis `100ml`.

| Nutrient | Explicit OFF per serving | Source per 100 mL | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 140 | 39.437 | — | 140 |
| Protein (g) | 0 | 0 | — | 0 |
| Fat (g) | 0 | 0 | — | 0 |
| Saturated fat (g) | — | 0 | — | 0 |
| Carbohydrate (g) | 39 | 10.986 | — | 39 |
| Sugars (g) | — | 10.986 | — | 39 |
| Fibre (g) | — | 0 | — | 0 |
| Sodium (mg) | — | 7.042 | — | 25 |

All reverse-scaled servings here are volume calculations. Derived per-100 g is unknown for every nutrient; gram logging must be unavailable until density is supported.

Additional OFF energy assertion: `186.761 kJ/100 mL` (unit interpretation follows the declared basis). Preserve independently and verify against kcal.

**Record servings:** 1 serving/can = 355 mL; no gram conversion. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Cola · Coca-Cola** — “1 serving (355 ml)”, 140 kcal. The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“cola / Coke”**: generic words should yield concept `cola` → `cnf:5288`. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `06782900` → `gtin:00067000008290` → `cola` → this record’s own nutrition and servings.

### 16. Plain Cheerios — General Mills

**Concept:** `toasted-oat-rings` — Toasted oat ring cereal. Path: **Cereals and grains → `toasted-oat-rings`. New attachment concept, seedable from the selected CNF row. Own shared image asset `toasted-oat-rings`.

**Default:** `cnf:1475`. **Verdict: breaks.** cnf:1475 explicitly names Cheerios, General Mills. It is a reference default for this ring-cereal concept only by judgement, not an unbranded generic. Calling it Generic misrepresents it, and treating it as the same record as this GTIN would erase differing values (397 versus 370.370 kcal/100 g). Keep two records, one product identity relationship, source-independent branded/reference roles, and brand-aware search ranking. Searching cheerios currently has two branded candidates; choose the verified current package only with a documented selection rule, otherwise show a choice. Concept-only title loses Plain versus Honey Nut; add record variant text.

**Record:** `gtin:00065633132818`; raw scan `0065633132818` → GTIN-14 `00065633132818`. Supplied serving string: **“27g”**; quantity field `27 g`; nutrition basis `100g`.

| Nutrient | Explicit OFF per serving | Source per 100 g | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 100 | 370.37 | 370.37 | 100 |
| Protein (g) | 4 | 14.815 | 14.815 | 4 |
| Fat (g) | 2 | 7.407 | 7.407 | 2 |
| Saturated fat (g) | — | 1.481 | — | 0.4 |
| Carbohydrate (g) | 20 | 74.074 | 74.074 | 20 |
| Sugars (g) | — | 3.704 | — | 1 |
| Fibre (g) | — | 11.111 | — | 3 |
| Sodium (mg) | — | 629.63 | — | 170 |

For nutrients without explicit per-serving values, the source per-100 g column is the available record assertion; no new precision is claimed.

Additional OFF energy assertion: `1874.074 kJ/100 g` (unit interpretation follows the declared basis). Preserve independently and verify against kcal.

**Record servings:** 27g (27 g); package = 350 g. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Toasted oat ring cereal · General Mills** — “27g”, 100 kcal. The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“Cheerios / oat ring cereal”**: generic words should yield concept `toasted-oat-rings` → `cnf:1475`. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0065633132818` → `gtin:00065633132818` → `toasted-oat-rings` → this record’s own nutrition and servings.

### 17. Dry roasted almonds — Kirkland Signature

**Concept:** `almonds-dry-roasted` — Almonds, dry roasted. Path: **Nuts and seeds → `almonds` → `almonds-dry-roasted`. New attachment concept, seedable from the selected CNF row. Inherits parent `almonds` image; the parent owns the asset `almonds-dry-roasted`.

**Default:** `cnf:2624`. **Verdict: fits with a rule.** cnf:2624, salted dry-roasted unblanched, matches sea salt in ingredients; 2536 is unsalted. Selecting salted as the concept default is a judgement call because salted/unsalted look alike. Keep salt state as a searchable record qualifier, not a nutrition-created concept. OFF unit ml contradicts the explicit “28 g”; use 28 g only as a documented correction supported by the serving text, still pending photo verification. 170/28 × 100 = 607.143 kcal differs slightly from OFF 607 due to rounding. Do not import CNF quarter-cup mass 35 g for this product.

**Record:** `gtin:00096619723829`; raw scan `0096619723829` → GTIN-14 `00096619723829`. Supplied serving string: **“1/4 cup (28 g)”**; quantity field `28 ml`; nutrition basis `100g`.

| Nutrient | Explicit OFF per serving | Source per 100 g | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 170 | 607 | 607.143 | 169.96 |
| Protein (g) | 6 | 21.43 | 21.429 | 6 |
| Fat (g) | 15 | 53.57 | 53.571 | 15 |
| Saturated fat (g) | — | 3.57 | — | 1 |
| Carbohydrate (g) | 5 | 17.86 | 17.857 | 5.001 |
| Sugars (g) | — | 3.57 | — | 1 |
| Fibre (g) | — | 10.7 | — | 2.996 |
| Sodium (mg) | — | 339 | — | 94.92 |

For nutrients without explicit per-serving values, the source per-100 g column is the available record assertion; no new precision is claimed.

Additional OFF energy assertion: `2539 kJ/100 g` (unit interpretation follows the declared basis). Preserve independently and verify against kcal.

**Record servings:** 1/4 cup = 28 g per explicit serving text, pending correction of OFF’s ml flag; package = 1130 g. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Almonds, dry roasted · Kirkland Signature** — “1/4 cup (28 g)”, 170 kcal. The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“almonds”**: generic words should yield concept `almonds-dry-roasted` → `cnf:2624`. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0096619723829` → `gtin:00096619723829` → `almonds-dry-roasted` → this record’s own nutrition and servings.

### 18. 1Yr Aged Canadian Cheddar — PC • Loblaws

**Concept:** `cheddar` — Cheddar. Path: **Dairy → `cheddar`. New attachment concept, seedable from the selected CNF row. Own shared image asset `cheddar`.

**Default:** `cnf:7735`. **Verdict: fits with a rule.** Use cnf:7735 old cheddar as a judgement-call default; one year is not a validated conversion to medium/old/extra old. 7737 medium and 7734 extra old remain alternatives, not aliases or substitute product nutrition. Nutrition similarity cannot settle age. Keep “1 year aged” as record variant text; otherwise the concept-only display hides why this cheese was selected. Ignore geographically wrong OFF category ancestry. Curate preferred brand President’s Choice (PC); retain PC and Loblaws as indexed source aliases.

**Record:** `gtin:00060383837464`; raw scan `0060383837464` → GTIN-14 `00060383837464`. Supplied serving string: **“30 g”**; quantity field `30 g`; nutrition basis `100g`.

| Nutrient | Explicit OFF per serving | Source per 100 g | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 130 | 433.333 | 433.333 | 130 |
| Protein (g) | 8 | 26.667 | 26.667 | 8 |
| Fat (g) | 10 | 33.333 | 33.333 | 10 |
| Saturated fat (g) | — | 20 | — | 6 |
| Carbohydrate (g) | 1 | 3.333 | 3.333 | 1 |
| Sugars (g) | — | 0 | — | 0 |
| Fibre (g) | — | 0 | — | 0 |
| Sodium (mg) | — | 700 | — | 210 |

For nutrients without explicit per-serving values, the source per-100 g column is the available record assertion; no new precision is claimed.

Additional OFF energy assertion: `1743.333 kJ/100 g` (unit interpretation follows the declared basis). Preserve independently and verify against kcal.

**Record servings:** 30 g (30 g); package = 250 g. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Cheddar · President’s Choice** — “30 g”, 130 kcal. The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“cheddar”**: generic words should yield concept `cheddar` → `cnf:7735`. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0060383837464` → `gtin:00060383837464` → `cheddar` → this record’s own nutrition and servings.

### 19. HUMMUS — President's Choice

**Concept:** `hummus` — Hummus. Path: **Spreads and dips → `hummus`. New attachment concept, seedable from the selected CNF row. Own shared image asset `hummus`.

**Default:** `cnf:4870`. **Verdict: fits.** cnf:4870 is commercial hummus and matches this product; the candidate is not homemade. CNF volume measures need not be inherited because the record already has 30 g and 454 g package servings. The product’s macros and salt differ; keep its own numbers. One generic unbranded hummus illustration suffices.

**Record:** `gtin:00060383035822`; raw scan `0060383035822` → GTIN-14 `00060383035822`. Supplied serving string: **“30 g”**; quantity field `30 g`; nutrition basis `100g`.

| Nutrient | Explicit OFF per serving | Source per 100 g | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 80 | 266.667 | 266.667 | 80 |
| Protein (g) | 3 | 10 | 10 | 3 |
| Fat (g) | 6 | 20 | 20 | 6 |
| Saturated fat (g) | — | 3.333 | — | 1 |
| Carbohydrate (g) | 5 | 16.667 | 16.667 | 5 |
| Sugars (g) | — | 0 | — | 0 |
| Fibre (g) | — | 6.667 | — | 2 |
| Sodium (mg) | — | 400 | — | 120 |

For nutrients without explicit per-serving values, the source per-100 g column is the available record assertion; no new precision is claimed.

Additional OFF energy assertion: `1246.667 kJ/100 g` (unit interpretation follows the declared basis). Preserve independently and verify against kcal.

**Record servings:** 30 g (30 g); package = 454 g. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Hummus · President's Choice** — “30 g”, 80 kcal. The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“hummus”**: generic words should yield concept `hummus` → `cnf:4870`. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0060383035822` → `gtin:00060383035822` → `hummus` → this record’s own nutrition and servings.

### 20. 100% Whole Wheat Thin Sandwich Bread — Wonder, Wonder Bread

**Concept:** `bread-whole-wheat` — Whole wheat bread. Path: **Bread → `bread` → `bread-whole-wheat`. New attachment concept, seedable from the selected CNF row. Inherits parent `bread` image; the parent owns the asset `bread-whole-wheat`.

**Default:** `cnf:4067`. **Verdict: fits with a rule.** Prefer cnf:4067 whole wheat commercial. cnf:7196 whole grain whole wheat is not established by “100% whole wheat” in this extract; keep it an alternative until label wording verifies whole grain. The generic choice is judgement. Thin is a record variant because slice thickness need not justify a different illustration. Offer 2 slices = 46 g and derived 1 slice = 23 g; never CNF’s 36 g or 33 g slice. The title rule hides Thin if another Wonder loaf is attached, so show variant. Ingredient OCR is damaged; no clean transcription can be claimed.

**Record:** `gtin:00063400136274`; raw scan `0063400136274` → GTIN-14 `00063400136274`. Supplied serving string: **“2 slices (46 g)”**; quantity field `46 g`; nutrition basis `100g`.

| Nutrient | Explicit OFF per serving | Source per 100 g | Derived per 100 g | Reverse-scaled serving, not verified print |
|---|---:|---:|---:|---:|
| Energy (kcal) | 120 | 260.87 | 260.87 | 120 |
| Protein (g) | 5 | 10.87 | 10.87 | 5 |
| Fat (g) | 2 | 4.348 | 4.348 | 2 |
| Saturated fat (g) | — | 1.739 | — | 0.8 |
| Carbohydrate (g) | 22 | 47.826 | 47.826 | 22 |
| Sugars (g) | — | 4.348 | — | 2 |
| Fibre (g) | — | 6.522 | — | 3 |
| Sodium (mg) | — | 413.043 | — | 190 |

For nutrients without explicit per-serving values, the source per-100 g column is the available record assertion; no new precision is claimed.

Additional OFF energy assertion: `1210.87 kJ/100 g` (unit interpretation follows the declared basis). Preserve independently and verify against kcal.

**Record servings:** 2 slices = 46 g; derived 1 slice = 23 g; package = 570 g. Record-specific measures take precedence; no generic piece/volume weight is imported without compatible record evidence.

**Display row:** **Whole wheat bread · Wonder** — “2 slices (46 g)”, 120 kcal. The table above supplies the remaining visible values; absent nutrients show —.

**Resolution:** Search **“whole wheat bread / Wonder thin”**: generic words should yield concept `bread-whole-wheat` → `cnf:4067`. A unique brand/product query should select this GTIN under the same concept; multiple matching records require a visible choice, not arbitrary first-match selection. Scan `0063400136274` → `gtin:00063400136274` → `bread-whole-wheat` → this record’s own nutrition and servings.

## Cross-cutting gaps and proposed fixes, ranked

These are the distinct gaps found in the twenty walkthroughs and in the lifecycle they require. P0 can cause materially wrong intake or identity; P1 blocks honest catalogue/search behaviour; P2 affects maintainability and predictable review. Proposed changes are recommendations, not changes made to the model.

| Rank | Gap and concrete evidence | Proposed field, rule or constraint |
|---|---|---|
| P0.1 | Mass-only `per100g` and gram-only servings cannot represent milk, chickpeas or cola (#2, #6, #15); oat drink units conflict (#9). OFF’s `_100g` suffix is not proof of grams. | Store `nutritionBasis:{quantity:100,unit:g|ml}`, typed serving quantities and package quantities. Optional `density:{gPerMl,evidence,measuredState}` permits conversion only when applicable to that product/profile. Preserve both quantities if a label explicitly supplies them. No implicit 1 mL = 1 g, no borrowed CNF density. Update the Food/Portion view to support volume without requiring fictitious grams. |
| P0.2 | A sold GTIN can have dry and prepared nutrition (#12); draining changes the measured food (#6). A single record/concept/profile pointer is insufficient. | Product record owns `profiles[]`, each with stable id, concept/form, `state` (as-sold, prepared, drained, etc.), nutrient basis, servings, preparation instructions, additions and yield evidence. Barcode selects product, then asks for state when necessary. Unknown state blocks applying a profile, not logging a provisional amount. No inferred dry↔prepared/drained conversion. |
| P0.3 | UPC-E #15 cannot be normalised by padding; eight digits can also be EAN-8, and a checksum can validate both. | Canonical GTIN-14 string plus `rawBarcode`, `symbology`, validation result and lookup aliases. Expand UPC-E to UPC-A first; pad valid GTIN-8/12/13 representations appropriately; preserve valid GTIN-14 package indicators. Never collapse distinct package GTINs by stripping arbitrary zeros. If symbology is absent and interpretation ambiguous, retain provisional identity and resolve with evidence before aliasing. |
| P0.4 | OFF extracts do not establish print, #4 has zero peanut protein, #13 impossible sodium, #5 conflicting energy and #17 wrong serving unit. Completed flags do not establish accuracy. | Separate immutable raw assertions from accepted `label` transcription, with evidence/photo reference, source field/unit, retrieval time, reviewer, correction reason and field-level `unverified/verified/disputed` status. Printed label remains null until verified. Validate dimensional consistency, positive serving amount, finite/nonnegative values, nutrient mass bounds and kcal/kJ consistency with tolerance. Flag, do not automatically “repair” from generic/macros. A disputed field can be — while verified fields remain usable. |
| P0.5 | Aliases for repackaging/corrections can erase a different formulation; the same GTIN can change over time (#5, #16 show why “same name” is insufficient). | Alias only proven identity duplicates; add immutable record revisions, effective dates and `replacedBy`/product-family relations for successors. Preserve original diary record id and logged revision/profile; resolve aliases without destructively rewriting history. A new barcode is not by itself evidence for nutrient equivalence. Alias graph must be acyclic, targets must exist, and resolution must terminate. |
| P0.6 | “Grams follow the record” makes all past one-pouch logs change after a serving correction. Today Portion stores a unit string and gram fallback; that cannot distinguish guessed portions from measured grams. | Diary stores stable `servingId`, quantity, profile/revision, original measurement unit and value, plus a logged nutrient/quantity snapshot or reproducible revision. Mark guessed versus measured weight. Permit an explicit reviewed correction for estimated portions; never change a user-weighed 53 g or past prepared recipe silently. Define history migration and undo. Stable food id alone is not stable intake. |
| P1.1 | #9–11 have no defensible CNF default; null is allowed for concept attachment but not clearly for default resolution. | Make `defaultRecordId` nullable with `defaultReason`, `defaultRole` and review status. No-default search returns the concept and record chooser or an honest “generic unavailable” path; it must not create a new pending food when the concept exists. A researched generic requires its own sourced record. Never substitute #9’s oat/quinoa blend. |
| P1.2 | CNF rows can be brands (#5, #16), contradicting both “CNF shows Generic” and generic-first selection. | Separate `source.kind` from `recordRole` (generic/reference/product/custom/recipe) and preferred brand. Display Generic only for genuinely generic records; a branded reference displays its brand and reference role without exposing provider. If a concept has no generic, apply the explicit no-generic policy. A default is not automatically a generic. |
| P1.3 | Granularity requires a different name AND picture, yet visually identical 0%/2% yogurt, salted/unsalted almonds and different-age cheddar need clear selection (#2–4, #17–18); inherited child images undermine the AND test. | Define concepts by culinary identity/preparation/physical form; allow shared images independently. Keep non-visual nutrition/marketing variants as structured record qualifiers (fat %, salt state, flavour, ageing, size/thickness), not new concepts. State when preparation deserves a child even if the image is inherited. A registry/lint rule prevents one concept per brand. |
| P1.4 | Display hides Plain Cheerios, Thin Wonder, one-year cheddar and future variants of a Kirkland bar (#10, #16, #18, #20). “Egg, large” in the example cannot come from the provided raw-egg concept. | Display concept title plus concise record variant/product text when needed to distinguish records; preferred brand remains subtitle. Serving size is shown in the portion control. Keep full product name accessible. Distinct selectable records must not have indistinguishable rows. Unknown brand is blank/Unbranded, not Generic by inference. |
| P1.5 | Generic-first search and “oreo finds the Oreo record” are not a complete ranking/resolution algorithm. General Mills/Quaker have multiple records, and CNF/GTIN can both match one brand (#5, #16). | Search returns typed hits `{conceptId,recordId?,matchKind}`. Generic terms rank curated concept defaults; explicit product/brand/qualifier queries rank matching records. Exact product matches outrank loose brand matches, but ties show choices. Index all brand aliases and multilingual names separately; no silent first-brand or first-record selection. Do not alias CNF and GTIN merely to deduplicate search. |
| P1.6 | Broad concepts have arbitrary defaults: milk 2%, yogurt 0%, salted almonds, old cheddar. Similar nutrition is not evidence of identity. | Curate one default with rationale, compatible concept/state and review metadata; expose qualifiers on the reference. Specific “unsalted almonds” must filter to an unsalted record, not resolve through the salted default. Require a deliberate fallback when a qualified generic is unavailable. CNF name-search hits are suggestions only. |
| P1.7 | “Own servings win” does not say replace versus merge. Biskwi has no cookie count; CNF slices/quarter cups differ from the branded products (#8, #17, #20). | Use stable serving ids and typed quantities. Record-specific servings replace unsafe concept conversions; inherit only verified compatible measures with explicit provenance. Derive 1 item from N items with count arithmetic, retaining precision. Global g/oz are mass units, not inferred product portions. Do not offer a concept package serving. |
| P1.8 | Package mass, edible mass, volume and serving differ (#1, #2, #6, #10–12). Package text may be junk or describe multiple units. | Separate `package:{netQuantity,unit,itemCount,edibleBasis}` from servings; validate structured fields against raw package text. A valid numeric package is not enough if state differs (#12). Null package is valid; drop junk display text while retaining evidence. Shell/drainage/refuse and multipack conversions require evidence. |
| P1.9 | Intake is described for missing fields but not disputed complete data, brand-bearing CNF or unresolved profile/default. Provisional records with null concept contradict concept-only display. | Allow review reasons independent of completeness, profile/field-level acceptance, and publication with explicitly unknown fields. Define provisional display fallback `{submittedName,submittedBrand}` and placeholder image until attachment. Use `catalogueStatus` separately from queue states; publish transactionally so concept/default/image/alias references cannot dangle. Require review of measured state and units, not just a label crop of numbers. |
| P1.10 | Two devices can mint different pending ids; a scan can predate symbology resolution; the old app uses `off:` ids. | Idempotent intake keys for canonical verified barcode and source record; provisional UUID remains resolvable forever via aliases. Add `off:<raw>` migration aliases and explicit handling for ambiguous raw eight-digit IDs. Never rename an identity because its concept name changes. Slug-like concept ids are immutable keys, not automatically regenerated names. Concurrent attachment and merge must not create cycles or orphan diary ids. |
| P2.1 | Concept count/image count cannot be inferred from the current granularity rule. It is unclear if sections/food parents are concepts and whether parent defaults delegate to forms. | Declare node kinds, allowed section→food→form edges, one canonical parent, acyclic hierarchy, section consistency and separate image asset references. Permit food-level records where no form is needed. A browsable food parent may route to a preferred form; enforce that its default resolves within that subtree and state. The explicit registry below is this report’s counting contract. |
| P2.2 | Images are per concept but children may inherit; a raw egg parent cannot stand for every cooked preparation. New variants could grow image cost without bounds. | `imageAssetId` with explicit inheritance/fallback and acyclic validation; generate once per distinct visual identity, never per barcode. Do not display a dry pasta image as prepared state without deliberate review. Product/label photos remain private evidence, not catalogue art. Define provisional/no-image placeholders and image publication status. |
| P2.3 | Brand strings are multi-valued/OCR-damaged (#3, #13, #18, #20), and current CNF puts French names in `brand`. | Separate localized names/synonyms, `brandAliases[]`, manufacturer and curated preferred display brand; keep raw text. French translations never become brands. Validate searchable accents and aliases (yogurt/yogourt, chickpea/garbanzo, Coke/Coca-Cola, Kraft Dinner/KD). Do not trust OFF category geography for tree placement. |
| P2.4 | No nutrient schema is shown for units, missingness, precision or competing energy assertions. #13 lacks total carbs; #15 lists caffeine but no amount. | Define canonical nutrient units and semantic basis; distinguish unknown, declared zero, below-threshold and disputed values. Preserve source rounding and asserted units; derived fields carry derivation and do not overwrite evidence. Prefer the verified declared kcal field over computed macro energy, but flag inconsistent kJ separately. Salt→sodium is an explicit derivation, not a borrowed nutrient. |
| P2.5 | Source invisibility can be misread as deleting provenance/licensing; record revisions and OTA catalogue delivery need an atomic data contract. | Keep provider, source code/version/retrieval and field provenance internally and credits/licences outside food rows. Ship a versioned validated catalogue manifest, migrations and alias table together; cache provisional overrides until accepted and support rollback/offline resolution. Delivery mechanism remains an open decision, not solved by this report. |

### Evidence that should not be promoted to “label as printed”

No label photo was available in this review. #5 has 112 kcal/30 g versus 375 kcal/100 g; #17 has 170 kcal/28 g versus rounded 607 kcal/100 g. These may reflect rounding or mixed inputs, not necessarily incorrect labels. #13 sodium, #4 protein and #9/#12 unit/state conflicts are stronger reasons for field review. Many OFF kcal and generic `energy_100g` kJ values disagree beyond ordinary display rounding (for example #10: 450 kcal versus 2242.5 kJ per 100 g). Never reconstruct an authoritative label by selecting convenient values from these columns.

Ingredient OCR is damaged or truncated for #10, #14 and #20. The report does not use that text to establish allergen completeness or verified ingredient percentages. Product “completeness” scores and `nutrition-facts-completed` selection are not evidence of correctness. This review makes no claim that supplied OFF values describe the current retail formulation.

## Principle check

| Decided principle | Does it survive these twenty? | Bad experience if applied literally; repair |
|---|---|---|
| Source invisible | Yes for provider names in ordinary food rows; no for source-derived branding. | #5 and #16 falsely show Generic solely because their branded measurement is in CNF. Keep source invisible but show brand/reference role. About/credits and provenance can still satisfy attribution requirements. |
| Generic first, barcode for accuracy | Works for direct generic overlap; incomplete for #9–11 and ambiguous broad defaults. Barcode identifies a product, not verified accuracy. | #9 gets the wrong oat/quinoa nutrition or no result; #10–11 have no generic. #12’s barcode returns an ambiguous prepared profile; #4/#13 can return bad numbers. Allow no generic, qualified generic choices, state selection and visible uncertainty. Do not silently return a branded default as generic. |
| No backfill | Holds if enforced per field and per measurement basis, not merely per nutrient map. | Nutella has unknown carbs and accepted sodium pending review; Coke caffeine is unknown; #4 protein must be disputed rather than borrowed. #2/#6/#15 lack product gram conversions, so source-only data cannot support grams. Preserve the useful volume portions and do not fill their density, serving weights or preparation factors from siblings. Lower micronutrient coverage after a scan is honest; say “not provided” instead of displaying misleading zero totals. |
| Images per concept, never branded | Holds with shared asset references and defined granularity. | No product needs packaging art. #7/#8 and #13/#14 share images. Visually similar variants need record qualifiers, not additional art. #11 stays one composite image. An inherited image alone cannot communicate 0% yogurt, salted almonds or thin bread; the display must carry those qualifiers. |
| IDs stable | Possible with canonical keys, aliases and revisioned evidence; not guaranteed by current wording. | Padding UPC-E #15 creates the wrong key. #12’s later state correction and #16’s CNF/GTIN identity distinction must not change what past logs mean. Preserve original ids, resolve aliases safely, and version nutrition/serving semantics. Automatic “grams follow the record” otherwise produces a bad history despite unchanged ids. |

These repairs preserve the intent of the principles. They do not authorize backfill, brand artwork, learned default brands or decomposition of composite meals. A literal implementation needs changes before the principles can all hold together.

## Concept and image accounting

“Seedable” means the chosen CNF row could create that concept before a product is attached. There is no proposed-concept registry in the repo proving which seed concepts are already published, so claiming those identities already exist would invent state. The first product encounter is marked new/seedable; only #8 and #14 unambiguously reuse concepts from another tested product. CNF alternatives not selected below are not silently imported.

| Attached concept | Products | Section | Parent food concept if a form | Default | New image assets |
|---|---|---|---|---|---:|
| `egg-whole-raw` | 1 | Eggs | `egg` | cnf:125 | 1 |
| `milk` | 2 | Dairy | — | cnf:61 (2%, judgement) | 1 |
| `yogurt-greek-plain` | 3 | Dairy | `yogurt` | cnf:6979 (0%, judgement) | 1 |
| `peanut-butter-smooth` | 4 | Nuts and seeds | `peanut-butter` | cnf:3399 | 1 |
| `oats-rolled-dry` | 5 | Cereals and grains | `oats` | cnf:1464 (branded reference) | 1 |
| `chickpeas-canned` | 6 | Legumes | `chickpeas` | cnf:3279 (state judgement) | 1 |
| `chocolate-sandwich-cookie` | 7, 8 | Snacks | — | cnf:3819 | 1 |
| `oat-drink` | 9 | Drinks | — | none | 1 |
| `protein-bar` | 10 | Snacks | — | none | 1 |
| `chicken-burrito-bowl` | 11 | Meals | — | none | 1 |
| `macaroni-cheese-box-dry` | 12 | Meals | `macaroni-cheese` | cnf:7140 (closest reference) | 1 |
| `cocoa-hazelnut-spread` | 13, 14 | Spreads and dips | — | cnf:5736 | 1 |
| `cola` | 15 | Drinks | — | cnf:5288 | 1 |
| `toasted-oat-rings` | 16 | Cereals and grains | — | cnf:1475 (branded reference) | 1 |
| `almonds-dry-roasted` | 17 | Nuts and seeds | `almonds` | cnf:2624 (salted, judgement) | 1 |
| `cheddar` | 18 | Dairy | — | cnf:7735 (old, judgement) | 1 |
| `hummus` | 19 | Spreads and dips | — | cnf:4870 | 1 |
| `bread-whole-wheat` | 20 | Bread | `bread` | cnf:4067 | 1 |

The eight parent food concepts own the same image assets their listed forms inherit, and route to their listed preferred form for unqualified search/browse; they introduce no additional nutrition records or art. The other ten attached concepts are food-level nodes with no extra form node. This uses the draft’s ability to stop at food level; forcing a redundant form for every food would add ten nodes without clarifying identity.

Totals: **20 product records; 18 attached concepts; 8 additional parents; 26 food/form concepts; 10 sections; 36 tree nodes including sections; 18 unique image assets.** There are 15 distinct selected CNF default records for 15 concepts and three nullable defaults. Thus this proposed subset has 35 measured records before any new researched generics or additional preparation profiles. These counts are design requirements, not a claim that this repository already contains the illustrations.
