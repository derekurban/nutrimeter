# Nutrimeter · app

Flutter, no code generation. Dependencies: `mobile_scanner` (camera barcodes), `http`, `path_provider`.
State is one `ChangeNotifier` (`AppState`) saved as a JSON file in the app's private storage.

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
| `lib/ui/` | `diary` (home), `food_picker` + `food_detail` (search and log), `scanner`, `recipes`, `custom_foods`, `settings` (targets, data, attribution), shared `widgets`, `nutrition` panels, `theme` |
| `test/` | `logic_test.dart` (targets, recipes, OFF parsing, the real CNF asset, backups) and `widget_test.dart` (log a food end to end) |

## Dev loop

```
flutter test                     # logic + widget tests
flutter analyze
flutter run                      # on a phone or emulator
```

The `Nutrimeter_API_36` emulator (Pixel 9 Pro, Android 16, 8 GB data) is set aside for this app:

```
"%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe" -avd Nutrimeter_API_36 -no-boot-anim -port 5560
```

Its camera has no feed, so barcode scanning has to be tried on a real phone.

## Builds

```
flutter build apk --release --split-per-abi --target-platform android-arm64   # phones, ~25 MB
```

Release builds are still signed with the debug key; a release keystore and CI releases (like easyday's) are next.

## Behaviour worth knowing

- **Food ids** are `off:<barcode>`, `cnf:<code>`, `custom:<id>`, `recipe:<id>`. OFF and CNF foods you log are kept in
  `savedFoods`, so the diary resolves them offline and before the CNF finishes loading at startup.
- **Grams follow the food**: an entry stores quantity + unit; its grams are recomputed from the food's current servings,
  so a logged "1 serving" of a recipe follows later edits to the recipe.
- **Deleting** a custom food or recipe archives it; old diary entries keep working.
- **Open Food Facts etiquette**: one product request per scan, search only on submit, `User-Agent: Nutrimeter/<v>
  (+repo)`, and at most 12 product reads / 8 searches per minute per device (OFF allows 15 / 10 per user).
