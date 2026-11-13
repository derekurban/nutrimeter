# Nutrimeter · app

Flutter, no code generation. Dependencies: `mobile_scanner` (camera barcodes), `image_picker` (label photos),
`supabase_flutter` (food review: sign-in, catalogue, publishing), `crypto` (photo hashes), `http`, `path_provider`,
`lucide_icons_flutter`. State is one `ChangeNotifier` (`AppState`) saved as a JSON file in the app's private storage.
In-app updates and links are two small method channels in `MainActivity.kt`.

## Layout

| Path | What |
|---|---|
| `lib/data/nutrients.dart` | The tracked nutrients: units, groups, adult DRIs and limits, scaling helpers |
| `lib/data/model.dart` | Foods, servings, diary entries, recipes, profile and targets, with hand-written JSON |
| `lib/data/store.dart` | `AppState`: diary, saved/custom foods, recipes, targets, recent, the catalogue cache and label reviews; resolving ids (through aliases); persistence, export/import |
| `lib/logic/foods.dart` | Resolving foods, servings and grams, recipe totals (recipes can nest; cycles are cut) |
| `lib/logic/barcode.dart` | Barcodes to GTIN-14: check digits, padding, UPC-E expansion |
| `lib/logic/targets.dart` | Mifflin–St Jeor BMR, energy and macro targets, overrides, progress |
| `lib/services/cnf.dart` | Loads `assets/cnf/foods.json` in an isolate and searches it (English and French names) |
| `lib/services/backend_config.dart` | The Supabase project per build: the dev branch for debug, the staging branch for staging, the main project for prod, or `NUTRIMETER_BACKEND` (publishable keys) |
| `lib/services/backend.dart` | Supabase from the app's side: start-up, sign-in, catalogue sync on launch and resume (every resume while products wait for review), publishing accepted label reviews |
| `lib/services/catalogue.dart` | The published catalogue: download, offline cache, record → `Food`, aliases, search |
| `lib/services/submissions.dart` | Label photos on the phone, a label review's idempotent upload, the submissions history with statuses |
| `lib/services/taxonomy_asset.dart` | The food taxonomy bundled as `assets/taxonomy.json` (identical in dev, staging and prod, without pictures), used until the taxonomy first syncs; regenerate it if a migration changes the categories. The taxonomy and its pictures sync without an account (`20261107130000_public_taxonomy.sql`), so pictures show signed out. `BundledArt` draws the pictures from `assets/art/` (`python -I tool/gen_art.py` before a release; about 2 MB), so they show offline and only pictures accepted after the build are downloaded |
| `lib/services/llm.dart` | Anthropic Messages API (streamed) and OpenAI Responses API over plain HTTP: photos in, schema-constrained JSON out, tokens and cost |
| `lib/services/reading_settings.dart` | API keys (Android Keystore), which model does each reading step, the confidence bar, spend |
| `lib/services/label_pipeline.dart` | Runs a label review on the phone, step by step, saved after each step |
| `lib/logic/label_reading.dart` | The pure part of label reading: schemas, briefs, checks, review lines with confidence, the record a review publishes |
| `lib/data/label_review.dart` | A product being read and reviewed on the phone: photos, every model call, readings, decisions, publish state |
| `lib/logic/update.dart` | Updates and feedback, the pure part: reading GitHub releases, picking one, comparing versions, issue links |
| `lib/services/platform.dart` | The Android calls behind updates and links (`MainActivity.kt`, `UpdateReceiver.kt`) |
| `lib/ui/` | `diary` (home), `food_picker` + `food_detail` (search and log), `scanner`, `product_flow` (a new find: photos, reading, review), `label_review_screen` (the review against the photos), `added_products` (what was added from labels), `reading_settings_page` (keys, models, the add-a-key prompt), `review` (sign-in card, submissions history), `recipes`, `custom_foods`, `settings` (targets, food review, data, updates, feedback, attribution), `updates` (the updater, its panel and trail, feedback links), shared `widgets`, `nutrition` panels, `theme` (below) |
| `test/` | `logic_test.dart` (targets, recipes, the real CNF asset, backups), `barcode_test.dart` (GTIN normalisation), `catalogue_test.dart` (record → food, aliases, old saved foods, products kept for the retired desktop queue becoming label reviews, submission status, build config, barcode lookup, sync throttle, a diary row filling in after review), `label_reading_test.dart` and `llm_test.dart` (label reading), `reading_key_test.dart` (no reading without a key), `update_test.dart` (releases, versions, issue forms) and `widget_test.dart` (log a food end to end; a search miss leads to the photos screen) |
| `tool/` | `icons.py` (below) |

## Design

The UI uses [derekurban/design-system](https://github.com/derekurban/design-system) v0.1.0, the same way easyday does:
`lib/ui/theme.dart` carries its tokens (`context.du`) as a Material theme, the type is Albert Sans for titles and Wix
Madefor Text for everything else (`assets/fonts/`, OFL), and icons are Lucide. Data follows the system's rules: series
are gray, the three macros told apart by lightness (protein darkest, fat lightest); a bar turns accent green when its
target is met and danger red when a limit is passed. Colour never decorates.

## Playground: the facelift

The 2026-11 facelift is being settled on the phone.

**The model** the rounds arrived at: the diary is a meter, not a meal log. What matters is the day's total in four
buckets (calories, protein, carbs, fat) and a few **standout** nutrients the person picks; every other nutrient is one
tap away. Which meal a food belonged to does not matter, so outside the original layout there are no meals: one list
of the day's food (a food is still stored with the meal for its time of day, so nothing is lost).

**The layout** (`lib/ui/diary_layouts.dart`) is a top section and the day's food under it. The top section is one
panel: the calories with a bar, a ring for each macro, and the standouts as shaded cells. Tapping it opens the full
breakdown, and the two candidate layouts differ only in how:

| Layout | Tapping the top section |
|---|---|
| Unfold | unfolds the breakdown inside the panel; the food moves down |
| Sheet | slides the breakdown up as a sheet over the diary |
| Original | (a summary, a card per meal, nutrient bars: what the app uses outside playground mode) |

The **breakdown** is one cell per nutrient under Carbs, Fats, Vitamins, Minerals and Other, each alphabetical. A cell
deepens toward the accent as its target fills and turns the full accent at 100%; a limit stays gray until it is
passed, then danger. Tapping a cell shows its numbers and makes it a standout or not; "Choose standouts" lists them
all. The standouts are kept with the playground's choices for now, not in the data file.

**The theme** (`lib/ui/looks.dart`) is Crisp: warm white, near-black ink, the berry icon's plum, raspberry and
lavender for the macros and leaf green for a target met as the only colour, set in Geist with heavy titles and
figures. Night is Crisp on warm black; they are two tabs while the light one is judged and are meant to become one
theme that follows the phone. A theme is colour tokens (`Du`) plus a `LookStyle` (faces, corners, shadows, bars);
widgets read both, and surfaces are `Panel`s, not `Card`s, so the whole app follows.

How it got here: six looks; crosses of the two kept (Orchard, Jam), which showed that repainting one structure was
not the answer; structure split from colour (six layouts, seven schemes: Paper kept, the shaded grid liked); the meter
model with four arrangements and Paper in five faces (Board and Geist picked); then this arrangement, which is
Derek's own.

Playground mode (`lib/ui/playground.dart`) floats a draggable berry button over the app; it opens a dock with a row of
layout tabs and a row of theme tabs (the app stays live above it), a sample day for an empty install, and a way out.
Targets → Playground turns it on in any build. It is on by default in the `playground` flavour:
`app.nutrimeter.playground`, "Nutrimeter Playground", berries on aubergine, on the dev backend, installed beside the
real app. A push to the `playground` branch releases it as a prerelease carrying `nutrimeter-playground.apk`, and
installed playground apps update themselves from those. Once the layout is chosen it becomes the app, with Crisp, and
the playground goes.

## Dev loop

```
flutter test                     # logic + widget tests
flutter analyze
flutter run --flavor staging     # on a phone or emulator (dev backend)
flutter run --flavor staging --dart-define=NUTRIMETER_BACKEND=staging   # same, against the staging backend
```

The `Nutrimeter_API_36` emulator (Pixel 9 Pro, Android 16, 8 GB data) is set aside for this app:

```
"%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe" -avd Nutrimeter_API_36 -no-boot-anim -port 5560
```

Its camera has no feed, so barcode scanning has to be tried on a real phone (label photos can come from the
emulator's gallery instead).

## Builds, releases and updates

Two flavours on one dimension, so a try-out never touches the real install:

| Flavour | Application id | Name | Icon |
|---|---|---|---|
| `prod` | `app.nutrimeter` | Nutrimeter | berries on cream |
| `staging` | `app.nutrimeter.staging` | Nutrimeter Staging | berries on amber |
| `playground` | `app.nutrimeter.playground` | Nutrimeter Playground | berries on aubergine |

Every `flutter run` or `flutter build apk` needs `--flavor prod|staging`. Debug builds add `.dev` to the id ("Nutrimeter
Dev"), so a dev loop on a phone installs beside the real app instead of over it. The launcher icons (Android adaptive
and legacy, iOS) are made by `python -I tool/icons.py` (Pillow, numpy, scipy) from one piece of artwork,
`tool/icon-source.png`: a berry cluster on flat cream, full bleed. To change the icon, replace that file and run the
script again.

```
flutter build apk --release --flavor prod --target-platform android-arm64   # what CI ships, ~25 MB
```

An arm64 release does not start on the x86_64 emulator (Flutter's engine will not run under its ARM translation); to
try a release build there, build it with `--target-platform android-x64`.

Release builds are signed with the keystore named in `android/key.properties` (ignored by git; the keystore and a copy
of that file live in `~/.keys/nutrimeter/`). Without that file a checkout still builds, signed with the debug key, but
such a build cannot update an install signed with the release key.

### Branches and releases

Work lands on `dev`. Releases come from CI (`../.github/workflows/release.yml`), never from a laptop:

| Merge | Builds | GitHub release |
|---|---|---|
| `dev` → `staging` | staging flavour | `v<version>-staging.<versionCode>` with `nutrimeter-staging.apk` |
| `staging` → `main` | prod flavour | `v<version>-prod.<versionCode>` with `nutrimeter.apk`, marked latest |

Each run analyzes, tests, builds the flavour (arm64) signed with the release key and publishes the release. A push to
`dev` runs only the checks. `<version>` is `pubspec.yaml`'s version name (bump it, and `lib/version.dart` with it, for a
new version; a test fails if they differ); the versionCode is 100000 + the workflow's run number, so every build
installs over the last. A pull request into `staging` or `main` runs the same build as a check without releasing (the
APK is kept as a run artifact): open the PR, let it go green, merge, and the merge publishes. The signing key reaches CI
as repo secrets `KEYSTORE_BASE64` (the keystore, base64), `KEYSTORE_PASSWORD`, `KEY_ALIAS` and `KEY_PASSWORD`.

### Updates in the app

Installed apps update themselves (`AutoUpdater` in `lib/ui/updates.dart`). On launch, and on coming back to the front
at most every half hour, the app reads `api.github.com/repos/derekurban/nutrimeter/releases`, takes the newest release
carrying its own flavour's APK, and if it is a higher version (or the same version with a higher build number) it
downloads it, saves, shows "Updating to …", and installs it over itself through a PackageInstaller session; Android
closes the app and the new version opens next time. It waits while anything is open over the tabs (logging a food, a
dialog, the scanner), installs nothing in debug builds, and needs "install unknown apps" allowed for the app once
(Targets → Updates asks for it and still offers a manual check and Update button). On Android 12+ Android installs
without a prompt once the app is its own installer of record, that is from the second self-update on; the first one
(and every one before Android 12) shows Android's confirm screen. Play Protect may still ask to scan an APK it has not
seen.

Every check also feeds a trail to a waiting update, for whenever the install does not happen on its own: an amber dot
on the Targets tab and the Updates header, and a banner at the top of Targets whose "Go to update" scrolls to the
Updates section. They go away once a check finds the app current.

A test build can read its release list from somewhere other than GitHub:
`--dart-define=UPDATE_FEED=http://127.0.0.1:8765/feed.json`, a JSON list shaped like GitHub's whose asset URL points at
an APK served beside it, from the computer through `adb reverse tcp:8765 tcp:8765`.

### Feedback

Targets → Feedback opens the repo's issue forms (`../.github/ISSUE_TEMPLATE/`) in the browser with the version (and,
for a problem, the phone) filled in. `test/update_test.dart` fails if a field the app fills is renamed or made a
dropdown.

## Food review

The backend is Supabase (`../supabase/`, design in `../docs/food-model/`). The app talks to it directly with
`supabase_flutter`, signed in as the one user (Targets → Food review; sign-ups are off, the admin creates the account).
Debug builds use the `dev` branch, release builds of the staging flavour the `staging` branch and release builds of
the prod flavour the main project (`lib/services/backend_config.dart`). `--dart-define=NUTRIMETER_BACKEND=dev|staging|prod`
overrides that for any build, e.g. a debug APK against staging for an end-to-end test:
`flutter build apk --debug --flavor staging --dart-define=NUTRIMETER_BACKEND=staging` (any other value fails the
start-up of food review). Each project has its own accounts; any build not on prod names its backend on the Food review
card. Without signing in, or offline, everything else works as before.

- **Catalogue.** While signed in, the app downloads the published catalogue (the taxonomy `food_groups`,
  `food_subgroups` and `food_categories`, `records` with their `category_id`, each record's current `record_revisions`
  row, `aliases`) on launch and on coming back to the front at most every half hour, or every time (15 s apart at
  most, for the camera) while a product captured on this phone is not published yet, so an accepted product fills in
  when the app is reopened (Targets → Food review → Sync forces it). It caches it in the data file. A record becomes a `Food` with the record's id, name ("Unnamed product"
  if it has none, or the name given when the product was captured) and brand, its default profile's `per_100g`
  nutrients and `portions` as servings, and its GTIN. Its picture is purely cosmetic and never the record's own: its
  category's image from the public `taxonomy-art` bucket, else its subgroup's, else its group's, else the letter
  placeholder. A record without a category is "Uncategorized" and works like any other. Search lists records under
  Products, matching name and brand first, then the category, subgroup and group names ("cereal" finds a ready-to-eat
  cereal); the food page shows where it is filed as "Group › Subgroup › Category". A cache from before the taxonomy
  still loads (uncategorized, without pictures) until the next sync replaces it.
- **Scanning** reads EAN-13, UPC-A, EAN-8, UPC-E and ITF-14, ignores codes with a bad check digit and normalises to
  GTIN-14 (`gtin:<14 digits>`; UPC-E is expanded to UPC-A first). It looks in the catalogue, then saved foods, then
  custom foods. A miss, or a product of yours still waiting for review, first forces a catalogue sync while signed in
  (up to 8 s; offline or slow, it goes by what the phone has), so a product published since the last sync opens
  directly and one already captured opens instead of being photographed again.
- **A miss is never a dead end.** A scan miss, a typed barcode miss, or "Add a product" under any search is a new
  find, read from its label on the phone (below). The product reaches the catalogue only that way: the desktop review
  queue (Nutrimeter Admin) was retired on 2026-11-12.
- **Uploads.** A label review keeps its photos in `submissions/<id>/` in app storage, so it survives restarts. Once it
  is accepted, and while signed in, it is published in the background on launch and resume: the `submissions` row (its
  id minted on the phone), each photo to `label-photos/<uid>/<submission>/<sha256>.<ext>` and its `submission_photos`
  row, then `publish_device_review`. Each step tolerates having already happened, so a retry never duplicates anything.
  Targets → Food review → Submissions is the history of what was sent from the account, with its status: "Uploading"
  until published, "Accepted" once published, and for what went to the retired desktop queue "In review", "Rejected"
  (with the reviewer's comment) or "Closed" (still waiting in the queue when it was retired).
- **Products an older version kept for the desktop queue** (`pendingSubmissions` in the data file, never sent or not
  fully sent) become label reviews at the photos stage when the app is updated: the same id (so the same photo folder
  and submission row), photos, barcode, name and brand hints, note and provisional food id. They show on the diary
  with the products being read, and are read with a key like any other; the diary keeps logging against the
  provisional food until the reviewed record is published under its id or an alias points it there.

## Label reading on the phone

A scan or search that finds nothing is a new find: the person photographs the front and the nutrition table
(ingredients optional) and the label is read on the phone with their own Anthropic or OpenAI key (Targets → Label
reading; keys live in the Android Keystore via `flutter_secure_storage`, never in the data file or a backup, and are
checked with their provider before they are saved). Reading needs a key, and there is no other way in: without one the
photos screen offers only "Add an API key to read it here", and every other way a reading starts (trying again,
reading again, a retake, carrying on past a finding, sending notes back) asks for a key first and runs nothing
without one.

1. **First read** (default Claude Opus 5.5, or GPT-6.1 Sol with only an OpenAI key): the whole package transcribed, as
   in the admin's digitise-v1, plus a box for each line on its photo. A partly legible table, unusable photos, photos of
   different products or "not food" pause the reading with a retake-or-carry-on choice.
2. **Second read** (a different model, the other provider's when both keys exist): the nutrition photo alone.
3. **Checks** on the phone: the reads compared, calories against macros, fats, sugars, fibre, mass, claims, the
   ingredient order, servings per container.
4. **Verifier** (default Claude Fable 5.1 or GPT-6 Astra): only the lines still under the confidence bar, asked what
   the photo prints. Skipped when nothing is in doubt.

Each line gets a confidence (two agreeing reads 99%, a disagreement 45%, lowered by the reader's caveats and failed
checks, raised by a clear verifier reading). The review opens on the lines under the bar (90% by default, adjustable)
with the photo moved to each; notes for the verifier are sent together in one re-read. Accepting builds the record
in record schema 3 (`../docs/food-model/record-schema.md`, checked by the database), saves it as a food at once, opens
it for logging, and publishes it while signed in: the submission and photos are uploaded, then `publish_device_review`
(migrations `20261107120000_device_reviews.sql`, `20261112120000_record_schema_3.sql`) records the readings, the
person's review, the revision and the alias. Every step is saved, so a closed app resumes where it stopped; nothing is re-run unasked.

## Behaviour worth knowing

- **Food ids** are `cnf:<code>`, `custom:<id>`, `recipe:<id>`, catalogue records `gtin:<14 digits>` and `food:<slug>`,
  and provisional `pending:<uuid>`. Resolving an id goes through the catalogue (and its aliases) first. CNF and
  catalogue foods you log, and provisional foods, are kept in `savedFoods`, so the diary resolves them offline, before
  the CNF finishes loading, and from a backup on a phone that has not synced. Backups leave out the catalogue cache and
  label reviews (their photos are files on the phone).
- **Open Food Facts is gone.** Foods older versions saved from it (`off:<barcode>`) still load and are treated like
  provisional foods: the scanner finds them by barcode, and once the catalogue has that barcode they show the
  reviewed record.
- **Grams follow the food**: an entry stores quantity + unit; its grams are recomputed from the food's current servings,
  so a logged "1 serving" of a recipe follows later edits to the recipe.
- **Deleting** a custom food or recipe archives it; old diary entries keep working.
