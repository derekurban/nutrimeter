# Nutrimeter · review site

The local website where products photographed in the app are reviewed. It lists the queue, runs an AI review
through the local Codex app server, shows the photos beside what was read, and publishes on your accept. It also
lists every food in a database, shows the taxonomy and which parts of it have pictures, and has an agent illustrate
the taxonomy in batches of five for you to accept or reject. It runs only on your machine (`127.0.0.1`); the phone
never talks to it.

Design: `../docs/food-model/backend.md`. Schema and rules: `../supabase/migrations/`.

## Run

```
npm install
npm start                 # build the UI and serve http://127.0.0.1:4317/
npm run dev               # the same with hot reload
```

**Databases.** The switch at the top right picks the Supabase environment the whole site reads and writes:

| | Supabase | App builds that use it | Credentials |
|---|---|---|---|
| Dev | branch `dev` (`enbylsacypvbzzdoapyg`) | debug builds | `~/.keys/nutrimeter/supabase-dev.env` |
| Staging | branch `staging` (`xtcutyizsdmswptesyaq`) | staging releases | `~/.keys/nutrimeter/supabase-staging.env` |
| Prod | main project (`vkhnbxizgnyfmnfphrmk`) | prod releases | `~/.keys/nutrimeter/supabase-prod.env` |

Only environments with a credentials file are offered (`supabase branches get <name> -o json` for a branch,
`supabase projects api-keys` for the main project); nothing secret is in the repo. The site needs `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY`; the database tests also need `POSTGRES_URL_NON_POOLING`. Prod is marked with a band, as
everything accepted there reaches the phone on its next sync. Each environment has its own accounts: the prod app
signs in with an account made under **Settings** while Prod is selected.

| Variable | Default | |
|---|---|---|
| `NUTRIMETER_ENV` | `dev` | The environment the site opens on (and the database tests use) |
| `NUTRIMETER_REVIEWER` | your OS user name | The name recorded on every accept and reject |
| `NUTRIMETER_CODEX_MODEL` | Codex's default | Model for AI reviews |
| `NUTRIMETER_CODEX_EFFORT` | Codex's default | Reasoning effort for AI reviews |
| `NUTRIMETER_ART_MODEL` | the review model | Model for illustrations |
| `NUTRIMETER_ART_EFFORT` | `medium` | Reasoning effort for illustrations |
| `NUTRIMETER_ART_CONCURRENCY` | `3` | Illustrations generated at once within a batch |
| `NUTRIMETER_CODEX_BIN` | found on PATH | The Codex binary |
| `NUTRIMETER_ADMIN_PORT` | `4317` | |

Codex must be installed and signed in (`npm i -g @openai/codex`, then `codex login`).

## How a review works

1. A submission arrives from the app (or **Add a product** here): barcode, photos, hints. Status `queued`.
2. **Start AI review** claims it and lays out a scratch folder: the photos, `taxonomy.json` (every category with its path) and,
   on a retry, the rejected attempt. It starts a Codex thread there (`codex app-server`, workspace-write sandbox,
   no approvals) with the review instructions (`server/prompt.mjs`), the photos as images, and the extraction
   schema (`shared/extraction-schema.mjs`) as the turn's required output. Codex reads the label as printed, tags
   it under one existing category, or none. It cannot create categories.
3. The site validates the answer against the schema (built from the categories that exist now), derives per-100 g
   values and portions in the app's units, runs the checks (`shared/derive.mjs`), and records the attempt.
   Status `drafted`.
4. You compare the photos with the reading. **Accept and publish** (optionally after editing the answer; edits
   are recorded) or **Reject** with a comment, which the next AI attempt reads. Failing checks block publishing:
   every food needs grams, so a volume-only label needs a density. **Change category** picks another existing
   category (or none) and is recorded as an edit.
5. Accepting creates or updates the record (`gtin:<14 digits>` for barcodes) with its category, its first
   or next revision, and an alias from the app's provisional id. The app picks it up on its next sync. A
   published record can be re-filed under another category from its submission page, with a reason; that changes
   the index only, not the revision.

Photos, attempts, reviews, revisions and the event log cannot be changed or deleted, by anyone. Every step is in
the `events` table with its actor (`user:<id>`, `agent:codex/<model>`, `reviewer:<name>`, `admin:<name>`), and
**Show history** on a submission lists them.

## Foods and taxonomy

**Foods** lists everything the app can log in the selected database: published records (reviewed) and submissions
still in review (not reviewed; the app logs them as provisional foods by name and weight). Search matches name,
brand, barcode, id and category path. A record's page shows what the app receives: the current revision per 100 g,
which taxonomy node its picture comes from, its revisions, submissions, aliases and events, and **File under** to
re-file it.

**Taxonomy** shows the groups, subgroups and categories (USDA WWEIA, seeded by migration) with their pictures, how
many foods are filed under each, which nodes have no picture (and whose picture they borrow), and the uncategorized
foods ("Other"). The app shows a food's category picture, else its subgroup's, else its group's, else a letter.
**Copy** brings accepted pictures over from another environment, recorded as accepted here with the original
decision cited.

## Illustrations

Pictures are cosmetic and belong to taxonomy nodes, never to records. **Illustrate the next 5** (Taxonomy or Images)
picks five nodes without a picture or one waiting for review: groups first, then subgroups, then categories, with
nodes that have foods first. Or select up to five nodes on the Taxonomy page.

Each node gets its own Codex thread (`server/art.mjs`) in a scratch folder with the style references
(`art/references/`, accepted foodcards illustrations, plus the two latest accepted here). The instructions
(`server/art-prompt.mjs`) carry foodcards' "Clay / Pastel 01" style: matte pastel clay, three-quarter view, upper-left
light, about 75% of a square canvas, a genuinely transparent background, no brands, text or packaging. Codex picks a
generic subject for the node, generates the image with its image tool, and answers with the subject, prompt and alt
text. The site checks the file (transparency at the edges, square, subject size), uploads a 768 px WebP for the app
and the PNG as generated to the public `taxonomy-art` bucket, and records it in `taxonomy_art` as pending.

On **Images**, compare each picture on checker, light, dark and pastel backgrounds and at list size, fix the alt
text, then **Accept** (the node shows it at once; the app after its next sync) or **Reject** with a comment, which
the next attempt at that node reads. Pictures failing a check can only be rejected. Every illustration, decision and
prompt stays in `taxonomy_art` and the event log.

## Layout

| Path | What |
|---|---|
| `server/index.mjs` | HTTP server: the API, loopback-only and header guards, serves the UI |
| `server/review.mjs` | One AI review run: claim, scratch folder, Codex thread, validation, derive, record |
| `server/art.mjs`, `server/art-prompt.mjs` | Illustration batches: node choice, Codex threads, image checks, upload |
| `art/references/` | Accepted foodcards illustrations that every illustration turn attaches as style references |
| `server/codex.mjs` | JSON-RPC client for `codex app-server` over stdio |
| `server/prompt.mjs` | The review instructions and per-submission turn text |
| `server/catalogue.mjs` | Supabase reads and writes (service role: reads tables, writes only through the database functions) |
| `server/env.mjs` | The environments and their credentials files |
| `shared/` | Extraction schema, derivation and checks, barcode normalisation, nutrient keys |
| `ui/` | The React UI (Vite), built on the design system |
| `test/unit/` | Derivation, checks, schema strictness, barcodes, image checks, nutrient keys against the app |
| `test/db/` | The whole pipeline and illustration review against a branch, inside a rolled-back transaction |

## Tests

```
npm test                  # unit
npm run test:db           # database: dev branch (NUTRIMETER_ENV=staging for staging), rolled back, never prod
```

## Migrations

`../supabase/migrations/` is applied to the dev branch first, then staging, then the main project:

```
npx supabase db push --db-url "$POSTGRES_URL_NON_POOLING"   # dev or staging, with its credentials loaded
npx supabase db push --linked                               # prod, with SUPABASE_DB_PASSWORD from ~/.keys/nutrimeter/supabase.env
```

Grant privileges explicitly in migrations: newer branches give the API roles nothing by default.
