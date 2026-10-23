# Nutrimeter

A Cronometer-style prototype for food logging, nutrition tracking and custom meals, backed by [Open Food Facts](https://world.openfoodfacts.org).

```sh
npm install
npm run dev      # http://localhost:5173
```

### On your phone (Tailscale)

Camera barcode scanning needs HTTPS, so expose the dev server with `tailscale serve` (tailnet-only, real certificate):

```sh
npm run dev
tailscale serve --bg 5173        # → https://<machine>.<tailnet>.ts.net
tailscale serve reset            # stop serving
```

`*.ts.net` is already in Vite's `allowedHosts`.

## Features

- **Barcode scanning** – camera scanner (EAN-13/8, UPC-A/E) in the food picker and a one-tap **Scan** button on the diary. Uses the native `BarcodeDetector` where available (Android Chrome) and a bundled zxing-wasm decoder elsewhere (iOS Safari).

- **Diary** – day-by-day log grouped into Breakfast / Lunch / Dinner / Snacks. Amounts and units are editable inline; click an entry to see its nutrients alone. Per-meal menu: save as recipe, copy from previous day, clear.
- **Food search** – Open Food Facts name/brand search, barcode lookup (8–14 digits), history, custom foods and recipes in one picker. Selecting a product fetches its full record (micronutrients, serving sizes).
- **Nutrition tracking** – energy ring, macro targets, and ~40 nutrients across General / Carbohydrates / Lipids / Protein / Vitamins / Minerals with % of target and over-limit warnings.
- **Custom recipes** – build from any food (including other recipes), set servings, see per-serving and whole-recipe nutrition, log in one step. Diary entries follow later recipe edits.
- **Custom foods** – enter a nutrition label per serving or per 100 g, with multiple serving sizes; or copy an Open Food Facts product and correct it.
- **Targets** – Mifflin–St Jeor BMR × activity ± goal, or a manual kcal target; macro split in %; per-nutrient target/max overrides on top of adult DRIs.
- All data is stored in `localStorage`; export/import JSON from the Targets page.

## Notes

- `search.openfoodfacts.org` does not send CORS headers, so search goes through the Vite dev/preview proxy (`/off-search`). If the proxy is missing (e.g. static hosting), search falls back to the slower legacy `cgi/search.pl` endpoint. Product lookups call the v2 API directly.
- Open Food Facts is crowd-sourced and mostly packaged products: serving sizes and micronutrients are often missing or wrong. Missing values show as "–" rather than 0.
- Nutrients are stored per 100 g in display units (kcal, g, mg, µg); OFF's gram-normalized `*_100g` values are converted on import.

## Layout

```
src/lib/nutrients.ts  nutrient definitions, DRI defaults, scaling helpers
src/lib/off.ts        Open Food Facts client + normalization
src/lib/foods.ts      food/recipe resolution, servings, totals
src/lib/targets.ts    BMR/energy and target resolution
src/store.ts          zustand store persisted to localStorage
src/components/       FoodPicker, NutritionPanel, ServingInput, charts, modals
src/pages/            Diary, Recipes, Custom Foods, Targets
```
