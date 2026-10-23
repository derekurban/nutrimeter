# Nutrimeter · app

Flutter, no code generation. Dependencies: `mobile_scanner` (camera barcodes), `http`, `path_provider`, `lucide_icons_flutter`.
State is one `ChangeNotifier` (`AppState`) saved as a JSON file in the app's private storage. In-app updates and
links are two small method channels in `MainActivity.kt`.

## Layout

| Path | What |
|---|---|
| `lib/data/nutrients.dart` | The tracked nutrients: units, groups, adult DRIs and limits, Open Food Facts keys, scaling helpers |
| `lib/data/model.dart` | Foods, servings, diary entries, recipes, profile and targets, with hand-written JSON |
| `lib/data/store.dart` | `AppState`: diary, saved/custom foods, recipes, targets, recent; persistence, export/import |
| `lib/logic/foods.dart` | Resolving foods, servings and grams, recipe totals (recipes can nest; cycles are cut) |
| `lib/logic/targets.dart` | Mifflin–St Jeor BMR, energy and macro targets, overrides, progress |
| `lib/services/off.dart` | Open Food Facts client: product by barcode, submit-only search, rate cap, normalization |
| `lib/services/cnf.dart` | Loads `assets/cnf/foods.json` in an isolate and searches it (English and French names) |
| `lib/logic/update.dart` | Updates and feedback, the pure part: reading GitHub releases, picking one, comparing versions, issue links |
| `lib/services/platform.dart` | The Android calls behind updates and links (`MainActivity.kt`, `UpdateReceiver.kt`) |
| `lib/ui/` | `diary` (home), `food_picker` + `food_detail` (search and log), `scanner`, `recipes`, `custom_foods`, `settings` (targets, data, updates, feedback, attribution), `updates` (the updater, its panel and trail, feedback links), shared `widgets`, `nutrition` panels, `theme` (below) |
| `test/` | `logic_test.dart` (targets, recipes, OFF parsing, the real CNF asset, backups), `update_test.dart` (releases, versions, issue forms) and `widget_test.dart` (log a food end to end) |
| `tool/` | `icons.py` (below) |

## Design

The UI uses [derekurban/design-system](https://github.com/derekurban/design-system) v0.1.0, the same way easyday does:
`lib/ui/theme.dart` carries its tokens (`context.du`) as a Material theme, the type is Albert Sans for titles and Wix
Madefor Text for everything else (`assets/fonts/`, OFL), and icons are Lucide. Data follows the system's rules: series
are gray, the three macros told apart by lightness (protein darkest, fat lightest); a bar turns accent green when its
target is met and danger red when a limit is passed. Colour never decorates.

## Dev loop

```
flutter test                     # logic + widget tests
flutter analyze
flutter run --flavor staging     # on a phone or emulator
```

The `Nutrimeter_API_36` emulator (Pixel 9 Pro, Android 16, 8 GB data) is set aside for this app:

```
"%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe" -avd Nutrimeter_API_36 -no-boot-anim -port 5560
```

Its camera has no feed, so barcode scanning has to be tried on a real phone.

## Builds, releases and updates

Two flavours on one dimension, so a try-out never touches the real install:

| Flavour | Application id | Name | Icon |
|---|---|---|---|
| `prod` | `app.nutrimeter` | Nutrimeter | green bracket |
| `staging` | `app.nutrimeter.staging` | Nutrimeter Staging | amber bracket |

Every `flutter run` or `flutter build apk` needs `--flavor prod|staging`. Debug builds add `.dev` to the id ("Nutrimeter
Dev"), so a dev loop on a phone installs beside the real app instead of over it. The launcher icons (Android adaptive
and legacy, iOS) and `tool/icon.svg` are drawn by `python -I tool/icons.py`; change the mark there. The mark is the
design system's app sub-logo, like easyday's: the two brackets kept exactly, an apple in place of the scribble.

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

## Behaviour worth knowing

- **Food ids** are `off:<barcode>`, `cnf:<code>`, `custom:<id>`, `recipe:<id>`. OFF and CNF foods you log are kept in
  `savedFoods`, so the diary resolves them offline and before the CNF finishes loading at startup.
- **Grams follow the food**: an entry stores quantity + unit; its grams are recomputed from the food's current servings,
  so a logged "1 serving" of a recipe follows later edits to the recipe.
- **Deleting** a custom food or recipe archives it; old diary entries keep working.
- **Open Food Facts etiquette**: one product request per scan, search only on submit, `User-Agent: Nutrimeter/<v>
  (+repo)`, and at most 12 product reads / 8 searches per minute per device (OFF allows 15 / 10 per user).
