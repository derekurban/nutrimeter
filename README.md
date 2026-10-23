# Nutrimeter

An open-source nutrition tracker in the spirit of Cronometer: food logging, ~40 tracked nutrients against your
targets, and custom recipes and foods. Everything stays on your phone; no account, no server.

**Food data**
- **Generic foods** (produce, meat, grains, dairy) come from the [Canadian Nutrient File](https://www.canada.ca/en/health-canada/services/food-nutrition/healthy-eating/nutrient-data/canadian-nutrient-file-about-us.html)
  2026 (Health Canada): 5,993 foods with up to 173 nutrients, bundled in the app and searched on the device.
- **Packaged products** come from [Open Food Facts](https://world.openfoodfacts.org): a barcode scan is one
  product lookup, and text search only runs when you submit. Requests go straight from the phone, identify the app,
  and stay under a self-imposed cap below OFF's per-user limits. Products you pick are saved with your data.

**Android app:** `mobile/` is the Flutter app (Android and iOS projects; Android is what's built and tested).
Its layout, dev loop, builds and releases are in `mobile/README.md`. Releases (signed APKs) are on the
[releases page](https://github.com/derekurban/nutrimeter/releases); the installed app updates itself.

## Layout

| Path | What |
|---|---|
| `mobile/` | The Flutter app: `lib/` code, `test/`, `assets/cnf/foods.json` (generated) |
| `tool/gen_cnf.py` | Builds `mobile/assets/cnf/foods.json` from the CNF download (stdlib Python) |
| `data/cnf/` | CNF source notes: version, licence, nutrient mapping, judgement calls (`README.md`); `raw/` holds the download and is git-ignored |
| `prototype/` | The first web prototype (React + Vite) the app was designed from |
| `.github/` | `workflows/release.yml` (staging and prod releases on merge) and the issue forms the app's feedback opens |

## Regenerate the CNF asset

```
python -I tool/gen_cnf.py            # downloads the 2026 CNF zip into data/cnf/raw/ if missing
```

## Branches and releases

Work lands on `dev`. Merging `dev` into `staging` builds and publishes a staging release on GitHub; merging `staging`
into `main` does the same for prod (`.github/workflows/release.yml`). Installed apps find the newest release for their
flavour and update themselves. Open a pull request for each merge: it runs the same build as a check, and the merge
publishes. Details: `mobile/README.md`, "Builds, releases and updates".

## Licences

- Code: GPL-3.0 (`LICENSE`).
- Open Food Facts data: Open Database License (ODbL); product images CC BY-SA.
  "Contains data from Open Food Facts, available under the Open Database License."
- Canadian Nutrient File: "Contains information licensed under the Open Government Licence – Canada.
  Source: Canadian Nutrient File, Health Canada, 2026." Omega-3/omega-6 totals are summed from individual fatty
  acids and values are rounded to 4 significant digits (`data/cnf/README.md`).
