# Backend: an auditable review pipeline

Status: built, 2026-10-23. Where submissions, photos, reviews and the published catalogue live, and why
Supabase over Convex.

**Decided:** Supabase, with no server of our own. The app talks to Supabase directly; review happens on a
local website (`admin/`) that drives the local Codex app server. The main project is `vkhnbxizgnyfmnfphrmk`
(Canada Central, Pro plan) and development happens on its persistent `dev` branch (`enbylsacypvbzzdoapyg`).
Credentials live in `~/.keys/nutrimeter/`, never in the repo.

## Requirements

1. **Every published number traces back to photos.** A value on a record leads to the revision that set it,
   the review that accepted it, the extraction that proposed it and the photos it was read from.
2. **Evidence is never lost.** Photos, extractions and reviews are append-only. Corrections add a revision;
   nothing is overwritten or deleted.
3. **Three writers with different rights.** The app (you) submits photos and logs food. The agent claims
   submissions and writes extractions and artwork. Only a human review publishes.
4. **The app works offline.** Published records sync to the phone; CNF stays bundled; provisional records
   are usable before review.
5. **Personal scale.** One user, a few hundred products. Roughly 3 photos per product at about 300 KB after
   on-device compression is about 1 MB per product, so about 1,000 products fit in 1 GB.

## Why Supabase

| | Supabase | Convex |
|---|---|---|
| Flutter client | Official `supabase_flutter` (publisher supabase.io; 2.18.3, 2026-10-12; ~1.3M downloads in 30 days) | No official Dart client. Community `dartvex` (pure Dart; 0.2.0, 2026-06; ~900 downloads) and `convex_flutter` (Rust FFI; 3.0.1, 2026-02; ~1,000 downloads). Convex's feature-request board has a request for one. |
| Enforcing the audit rules | Postgres: foreign keys, CHECK constraints, triggers for an append-only event log, and row-level security that can deny UPDATE and DELETE outright. | Schema validation and transactional mutations; append-only is a convention kept in your function code, not something the database refuses. |
| Photos linked to data | Private Storage bucket with access policies; rows reference objects by path and sha256 (foodcards already did content-addressed paths). The link is by convention. | File storage IDs live inside documents, so the link is native. A real advantage. |
| Agents | SQL, the Supabase CLI and an official MCP server. Agents are fluent in SQL. | TypeScript functions, the Convex CLI and MCP server. Also workable. |
| Single-user auth | Supabase Auth with your account; policies like `owner = auth.uid()`. The agent's secret key stays server-side. | Convex Auth targets JS clients; a Dart app would need a custom JWT setup. |
| Free plan | 500 MB database, 1 GB files, 2 active projects. **Pauses after 7 days without activity; no automatic backups.** ([pricing](https://supabase.com/pricing)) | 0.5 GB database, 1 GB files, 1M function calls. Pausing for inactivity isn't documented. ([plans](https://www.convex.dev/plans)) |
| Paid plan | Pro $25/month: daily backups kept 7 days, no pausing, 100 GB files. | Professional $25 per developer/month: daily backups, 100 GB files. |
| History with you | foodcards' Supabase project (Canada Central) already has a catalogue schema, a private image bucket, read policies and migration tests. | foodcards started on Convex in January 2026 and moved to Supabase in September. |

Convex's main strength is end-to-end TypeScript with reactive queries in JS clients. A Dart app loses most of
that, and the audit trail benefits from a database that can refuse writes. Supabase fits better.

The org is on Pro: daily backups, no pausing, and branching for the `dev` environment.

## Data model

```
submissions ──< submission_photos            (evidence: immutable)
     │
     └──< extractions                        (agent proposals: immutable, one per attempt)
               │
               └──< reviews                  (human decisions: immutable)
                         │
                         └──> record_revisions ──> records ──> food_categories ──> food_subgroups ──> food_groups
                                                     ▲
                                                  aliases
events                                       (append-only log of every state change, written by triggers)
```

| Table | Holds | Written by |
|---|---|---|
| `submissions` | Raw barcode, symbology, canonical GTIN, provisional record id, the name you typed, status (`uploading`, `queued`, `claimed`, `drafted`, `accepted`, `rejected`), who claimed it, the published record | App inserts; agent claims |
| `submission_photos` | Role (`front`, `nutrition`, `ingredients`, `other`), object path, sha256, content type, dimensions, size | App |
| `extractions` | Agent and model, prompt version, the label as read, derived nutrition, profiles, the chosen category (or none) with reasons, automated check results | Agent |
| `reviews` | Decision, reviewer, notes, the diff between the extraction and what was accepted | You |
| `records` / `record_revisions` | Each accepted review creates a revision; the record points at its current one | `accept_extraction()` only |
| `food_groups`, `food_subgroups`, `food_categories` | The USDA WWEIA taxonomy that indexes records, with optional cosmetic images | Migrations only (seeded); `set_record_category()` re-files a record |
| `aliases` | Old id → new id | `accept_extraction()` only |
| `events` | Every insert and status change, with actor and time | Triggers |

Storage: a private `label-photos` bucket for evidence, and a public `taxonomy-art` bucket for the cosmetic
taxonomy images. (`concept-art` is left over from the concept layer and unused.)

Rules the database enforces:

- No UPDATE or DELETE on photos, extractions, reviews, revisions or events, for anyone, including the agent.
- Publishing happens only through one `accept_extraction(...)` function, which in a single
  transaction writes the review, the record and its category, the revision, any alias, and the event.
- A record's current revision must come from an accepted review.

## Where things run

- **App (Flutter):** signs in as you (email and password; sign-ups are off, the account is created on the review
  site). Submits the barcode, photos and hints straight to Supabase, logs the provisional food at once, and
  syncs the published catalogue for offline use. CNF stays bundled.
- **Review site (`admin/`, localhost only):** the queue, the photos beside each AI reading, and the decision.
  **Start AI review** runs a thread on the local Codex app server: the photos and the taxonomy go into a scratch
  folder, and the answer must match the extraction schema, whose category field only accepts existing
  categories or null. The site validates and derives everything, then records the attempt. Accept publishes;
  reject needs a comment, which the next attempt reads. See `admin/README.md`.
- **No GitHub issues.** The queue is the `submissions` table.

## Environments

| | Supabase | Used by |
|---|---|---|
| dev | `dev` branch (`enbylsacypvbzzdoapyg`) | debug and staging builds; `npm start` in `admin/`; database tests |
| prod | main project (`vkhnbxizgnyfmnfphrmk`) | prod builds; `NUTRIMETER_ENV=prod npm start` |

Migrations in `supabase/migrations/` go to the dev branch first, then to the main project.

## Migration from today

- foodcards' clay illustrations could become taxonomy images; its Supabase project can then be retired.
- Existing `off:<barcode>` foods in the app keep resolving and are treated as provisional.
