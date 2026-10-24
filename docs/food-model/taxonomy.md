# Taxonomy: when a new level is allowed

Status: decided and built on the dev branch, 2026-10-23. The hardest ongoing decision in the catalogue is whether something deserves its own
place in the tree. The first live review made this concrete: Codex filed Cheerios as a new food "Oat ring cereal"
directly under the section "Grains & cereals", the same level as rolled oats and brown rice would sit. This page
looks at how established food classifications handle the problem and proposes rules.

## Decision

```
Group       15 USDA WWEIA groups                 fixed
Subgroup    49 USDA WWEIA subgroups              fixed
Category    164 USDA WWEIA categories            the three nutrient-threshold splits merged; added only by a person
Record      category_id: one category, or null   null = uncategorized, our "Other"
```

1. **Records are the catalogue; the taxonomy only indexes them.** There is no concept level.
2. **A record has exactly one category, or none.** One category implies its subgroup and group; there is no
   partial classification. "Not included in a food category" from WWEIA is dropped because null means that.
3. **Merged:** Milk (whole, reduced fat, lowfat, nonfat), Flavored milk (the same four), and Ready-to-eat cereal
   (higher and lower sugar). The same food falls on both sides of a nutrient threshold, so thresholds are for
   insights calculated from a record's numbers, not for filing.
4. **The AI only picks:** an existing category or null, with its reason and the runners-up. The answer schema
   only accepts category ids that exist when the review runs, and the database refuses unknown ones. New
   categories are a separate, human-run review stream (not built yet).
5. **A reviewer can re-file** a published record without a new revision (`set_record_category`); the reason is
   in the event log.
6. **Images are cosmetic** and live only on groups, subgroups and categories (public `taxonomy-art` bucket). A
   record shows its category's image, else its subgroup's, else its group's, else a placeholder.
7. **Classify as eaten:** rolled oats are Oatmeal, a boxed macaroni dinner is Macaroni and cheese. Use an
   existing category whenever it is truthful, even when broad (an Oreo is Cookies and brownies). Mind WWEIA's
   splits: diet vs sweetened drinks, plain vs flavoured milk, fried vs baked potatoes, dried vs fresh fruit.

Source and generator: `supabase/seed-sources/wweia-2021-2023.txt` and `gen_taxonomy.py`, which writes
`supabase/migrations/20261024000100_taxonomy_seed.sql`. A newer WWEIA release becomes a new migration; ids are
slugs of the names and stay stable.

## How others do it

| System | Shape | What is allowed to grow | How variants are handled |
|---|---|---|---|
| **USDA WWEIA Food Categories** (dietary intake, the "as eaten" view) | Fixed 3 levels: 15 groups → about 50 subgroups → about 170 categories. Every food is in exactly one category. | Nothing, between releases: the list is revised per survey cycle by USDA. | Foods are classified as eaten, not disaggregated into ingredients. Some categories are split by a nutrient threshold: ready-to-eat cereal is "higher sugar (>21.2 g/100 g)" or "lower sugar (≤21.2 g/100 g)"; milk by fat level. |
| **GS1 Global Product Classification** (retail, barcoded goods) | Fixed 4 levels: segment → family → class → **brick**. The upper three exist only to find the brick. | Bricks, by change request to GS1. | Brick attributes (e.g. milk: cow, goat, soy, rice), not new levels. |
| **EFSA FoodEx2** (food safety and intake reporting) | One **base term** per food, plus up to a handful of **facets** from 28 facet categories (process, ingredient, packaging…). Several **hierarchies** are views over the same base terms. | Base terms and facet descriptors, centrally. | Facets. Different purposes get different hierarchies instead of one deeper tree. |
| **LanguaL** (food composition databases, e.g. CIQUAL) | No single tree: 14 facets (product type, food source, part of plant or animal, physical state, heat treatment, cooking method, packing medium…). | Facet vocabularies. | Everything is a facet. |
| **Open Food Facts categories** | A crowd-edited graph: categories may have several parents, no cycles. | Anything, by anyone. | New categories. |

### USDA WWEIA and GS1 GPC side by side

GPC paths come from GS1's combined publication of June 2020 (via the
[VladimirAlexiev/gs1-gpc](https://github.com/VladimirAlexiev/gs1-gpc) mirror: 23 food families, 124 classes,
791 food bricks); current releases have more bricks, with the same structure. WWEIA paths are from the 2021–2023
list.

| Food | USDA WWEIA (group → subgroup → category) | GS1 GPC (family → class → brick · attributes) |
|---|---|---|
| Cheerios | Grains → Ready-to-Eat Cereals → RTE cereal, lower sugar (≤21.2 g/100 g) | Cereal/Grain/Pulse Product → Processed Cereal Product → Cereals Products – Ready to Eat (Shelf Stable) · Type of Processed Cereal: oats · If Flaked: no |
| Rolled oats | Grains → Cooked Cereals → Oatmeal (as eaten) | Cereal/Grain/Pulse Product → Processed Cereal Product → Cereals Products – Not Ready to Eat (Shelf Stable) |
| 2% milk | Milk and Dairy → Milk → Milk, reduced fat | Milk/Butter/Cream/Yogurts/Cheese/Eggs/Substitute → Milk/Milk Substitute → Milk (Perishable) · Level of Fat Claim: reduced fat · Source: cow |
| Coca-Cola | Beverages → Sweetened Beverages → Soft drinks | Beverage → Non Alcoholic Beverages – Ready to Drink → Drinks Flavoured – Ready to Drink · Type: cola · If Carbonated: yes · If With Caffeine: yes |
| Diet Coke | Beverages → **Diet Beverages** → Diet soft drinks | Same brick as Coca-Cola · If With Diet/Light Claim: yes |
| Oreo | Snacks and Sweets → Sweet Bakery Products → Cookies and brownies | Bread/Bakery Product → Biscuits/Cooky → Biscuits/Cooky (Shelf Stable) |
| Eggs | Protein Foods → Eggs → Eggs and omelets | Milk/…/Eggs/Substitute → Eggs/Eggs Substitute → In Shell Table Egg |
| Apple | Fruit → Fruits → Apple | Fruits – Unprepared/Unprocessed (Fresh) → Pome Fruit → Apple |
| Kraft Dinner | Mixed Dishes → Grain-based → Macaroni and cheese | Prepared/Preserved Food → Grain Based Products / Meal → Grain Based Products / Meals – Not Ready to Eat – Savoury (Shelf Stable) |
| Peanut butter | Protein Foods → Plant-based Protein Foods → Nuts and seeds | No brick or attribute of its own in this release. It fits either Nuts/Seeds – Prepared/Processed (Shelf Stable), beside roasted almonds, or Other Sauces Dipping/Condiments/Savoury Toppings/Savoury Spreads/Marinades (Shelf Stable). (Nutella, by contrast, has Confectionery Based Spreads.) |

How they differ:

- **Purpose.** WWEIA classifies what people eat, for nutrition research. GPC classifies what retailers sell, for
  the supply chain, and covers non-food too.
- **What drives a split.** WWEIA splits on nutrition (sugar, fat, diet) and on how food is eaten (rolled oats are
  "oatmeal"). GPC splits on product form and logistics: shelf-stable, perishable and frozen are separate bricks,
  and fresh produce is fine-grained (a brick per pome fruit) while processed foods are coarse (peanut butter has
  no brick of its own and fits two).
- **Where variation goes.** WWEIA puts some variation into categories (reduced-fat milk, diet soft drinks). GPC
  puts it into **attributes with closed value lists** (Level of Fat Claim, If With Diet/Light Claim, If
  Carbonated, If Organic, Type of Flavoured Drink).
- **Coverage.** WWEIA covers what is never sold with a barcode: homemade and restaurant dishes, tap water,
  human milk. GPC covers only products, and brand owners assign the brick themselves in their product data.
- **Size and change.** WWEIA: about 170 leaves, revised every survey cycle. GPC: hundreds of food bricks and
  thousands of attribute values, revised twice a year by change request, with codes retired over time.

What to take from each: WWEIA's three levels as the backbone (its nutrient-threshold categories merged), because a
diary is about food as eaten;
GPC's habit of closed-value attributes as the model for facets, and some of its vocabularies (fat claim, diet
claim, carbonated, organic) as starting values. GPC's shelf-stable, perishable and frozen splits are logistics and
do not belong in a nutrition catalogue.

One consequence of adopting WWEIA: where it files variants in **different subgroups** (diet vs sweetened soft
drinks, flavoured vs plain milk, fried vs baked potatoes), those variants must be different concepts, because a
concept has one parent. That is consistent with the naming rule (Diet cola is named differently), but it means
the backbone, not only the picture, decides some splits.

Two lessons stand out:

1. **No serious system lets the tree grow levels case by case.** WWEIA, GS1 and FoodEx2 all fix the upper
   structure and let only the leaf grow, through a deliberate process. Open Food Facts lets anything grow, and its
   category graph is the least consistent part of its data.
2. **Variation is a facet, not a level.** GS1 attributes, FoodEx2 facets and LanguaL all describe "cooked",
   "flavoured", "2% fat" or "goat's milk" as properties of a thing, not as a deeper node.

Sources: [WWEIA Food Category List 2021–2023](https://ars.usda.gov/ARSUserFiles/80400530/pdf/2123/Food_Category_List_2021-2023.pdf),
[GS1: how GPC works](https://www.gs1.org/how-gpc-works),
[EFSA data standardisation](https://www.efsa.europa.eu/en/data/data-standardisation),
[FoodEx2 in MCRA](https://mcra.rivm.nl/documentation/9.2.1/modules/primary-entity-modules/foods/foodex2.html),
[LanguaL](https://langual.org), [LanguaL and FoodOn](https://pmc.ncbi.nlm.nih.gov/articles/PMC3352238),
[Open Food Facts categories taxonomy](https://wiki.openfoodfacts.org/Global_categories_taxonomy/FoodexHierarchy).

## Earlier proposals (superseded by the decision above)

Kept for the reasoning. The concept level and its rules below were dropped: records attach to categories
directly, and images moved to the taxonomy.

### A fixed backbone of three levels, a growing leaf, and facets

```
Group        fixed    WWEIA group            GRAINS
Subgroup     fixed    WWEIA subgroup         Ready-to-Eat Cereals
Category     fixed    WWEIA category         Ready-to-eat cereal      (merged from higher/lower sugar)
Concept      grows    what the food is       Oat ring cereal          ← one image, the only level the AI may add
Record       grows    one source's numbers   Cheerios · General Mills (gtin:00065633132818)
Facets       closed   how a record differs   flavour, fat level, salt, size, organic
```

- **All three WWEIA levels are the backbone**, copied once and versioned in a migration. WWEIA is built for
  exactly what a diary needs: foods classified as eaten, by people who measure intake. About 15 groups, 50
  subgroups and 160 categories cover everything from baby formula to cocktails, which the current 19 hand-made
  sections do not.
- **Categories defined by a nutrient threshold are merged**, because the same food falls on both sides of them
  (Cheerios and Honey Nut Cheerios are both oat ring cereal). WWEIA 2021–2023 has three such splits:
  - Milk: whole, reduced fat, lowfat, nonfat → **Milk**
  - Flavored milk: whole, reduced fat, lowfat, nonfat → **Flavored milk**
  - Ready-to-eat cereal: higher sugar (>21.2 g/100 g), lower sugar (≤21.2 g/100 g) → **Ready-to-eat cereal**
  The thresholds are still worth showing as insights ("high-sugar cereal"); they are calculated from the record's
  numbers, not stored as categories.
- **A concept sits in exactly one category.** Every remaining category describes what a food is (Apple, Pizza,
  Yogurt, Greek), so this holds. Where WWEIA puts variants in different categories or subgroups (diet vs
  sweetened soft drinks, French fries vs baked potatoes, dried fruit vs fresh), they are different concepts.
- **Categories with a single obvious concept** ("Apple" → Apple) are fine; the app collapses a level with one
  child when browsing.
- **Local extensions are new categories**, never new levels, added only as a recorded decision in a migration,
  never by the AI. The obvious ones come from foodcards' produce focus: WWEIA has no herbs and spices, and puts
  mushrooms and seaweed in "Other vegetables and combinations".
- **Other ways of browsing** (Canada's Food Guide plate, CNF food groups, "breakfast") are separate views mapped
  onto concepts, as FoodEx2 does with its hierarchies, never extra parents.

### Forms

WWEIA classifies food as eaten, so the forms of one food land in different places:

| Form | WWEIA category |
|---|---|
| Apple, raw | Fruit → Fruits → Apple |
| Dried apple | Fruit → Fruits → Dried fruits |
| Apple juice | Beverages → 100% Juice → Apple juice |
| Potato, baked | Vegetables → White Potatoes → White potatoes, baked or boiled |
| French fries | Vegetables → White Potatoes → French fries and other fried white potatoes |

So a form cannot be a child of its base concept. **Forms are separate concepts**, each in its own category with
its own image, linked to the base food by a non-hierarchical `form_of` relation (dried apple `form_of` apple).
The link keeps "apple and its forms" together for browsing and for the knowledge layer later, without a second
parent. This settles the open question from the decision list.

### The rules for concepts

1. **Classify as eaten.** Rolled oats are eaten as oatmeal: Grains → Cooked Cereals → Oatmeal, with an as-sold
   profile for the dry oats. Kraft Dinner is Mixed Dishes → Grain-based → Macaroni and cheese.
2. **Same name and same picture means the same concept.** Brand, flavour, fat %, salt, sugar level, size,
   organic and shape are facets or record details. A flavour gets its own concept only when it changes what the
   food is called and looks like (chocolate milk vs milk: different name, different colour, and a different
   WWEIA category; vanilla vs plain yogurt: same).
3. **A preparation that changes the picture or the category is a separate concept** linked by `form_of`.
4. **The AI picks a category; it never creates one.** If none fits, its answer says so (`needs_category`), and a
   person decides whether to extend the backbone. This is foodcards' "category request", made explicit.
5. **Concept names are generic and singular**, with no brand words, and the synonyms are words people would
   search for that mean the same food, never brand names.
6. **Before creating a concept, the AI must list the closest existing concepts and say why each does not fit.**
   This puts the hardest judgement in front of the reviewer instead of hiding it.

### How Cheerios would be filed

```
GRAINS
└── Ready-to-Eat Cereals
    └── Ready-to-eat cereal                               category (merged)
        └── Oat ring cereal                               concept, one clay image
            ├── Cheerios · General Mills                  record   3.7 g sugars/100 g → shown as lower sugar
            └── Honey Nut Cheerios · General Mills        record   flavour: honey nut → shown as higher sugar
```

Rolled oats would sit under GRAINS → Cooked Cereals → Oatmeal; brown rice under GRAINS → Cooked Grains → Rice.
Different subgroups, so "Grains & cereals" stops being a pile.

### The facets to start with

| Facet | Values (closed, extended by migration) | Set by |
|---|---|---|
| flavour | free text from the label | review |
| fat level | skim, 1%, 2%, whole, light, regular | review |
| salt | unsalted, lightly salted, salted | review |
| organic | yes or no | review |
| sugar level | lower, higher (WWEIA's 21.2 g/100 g for cereal) | calculated from the record, for insights |

GS1 GPC's brick attributes (fat claim, diet/light claim, carbonated, organic) are a good source for more values.

## What the earlier proposal would have changed

- A migration replacing the 19 seeded sections with WWEIA's groups, subgroups and categories (the three
  threshold splits merged), plus the chosen local extensions; a `form_of` link between concepts; a `facets`
  field on records.
- The extraction schema: `concept.category_id` must be a category; a new `nearest_concepts` list with reasons;
  a `needs_category` verdict; `form_of` for forms; facets instead of free-form qualifiers.
- The checks: reject a brand word in a concept name, a concept whose parent is not a category, and a new concept
  whose name matches an existing one or its synonyms.
- Mapping CNF's 23 food groups and its food names onto categories, so the 5,993 generic foods can seed concepts in
  the right place.

## Open

- **The category stream**: how new categories are proposed and reviewed, and which first (herbs and spices,
  mushrooms, seaweed).
