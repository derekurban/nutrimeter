-- The food review pipeline: submissions with label photos, AI extractions, human reviews, and the published
-- catalogue they produce. Evidence (photos, extractions, reviews, revisions, events) is append-only: triggers
-- refuse UPDATE and DELETE for every role, including service_role. Clients (the app) can only add their own
-- submissions and photos and read the published catalogue; everything else goes through the functions at the
-- bottom, which only service_role (the local admin) may call.

-- ── Helpers ────────────────────────────────────────────────────────────────────────────────────────────────

-- A GTIN-14 string with a valid check digit (EAN-13, UPC-A and expanded UPC-E codes are padded to 14 digits).
create function public.gtin_valid(code text) returns boolean
language sql immutable set search_path = '' as $$
  select code ~ '^[0-9]{14}$' and (
    (10 - (select sum(substr(code, i, 1)::int * case when i % 2 = 1 then 3 else 1 end)
           from generate_series(1, 13) as i) % 10) % 10
  ) = substr(code, 14, 1)::int
$$;

-- Who is acting: the admin and agent set `nutrimeter.actor` per transaction; the app is its auth user.
create function public.current_actor() returns text
language sql stable set search_path = '' as $$
  select coalesce(nullif(current_setting('nutrimeter.actor', true), ''),
                  'user:' || (select auth.uid())::text,
                  current_user)
$$;

create function public.forbid_change() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception '% is append-only: % is not allowed', tg_table_name, tg_op
    using errcode = 'insufficient_privilege';
end $$;

create function public.forbid_delete() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'rows in % cannot be deleted', tg_table_name using errcode = 'insufficient_privilege';
end $$;

create function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ── Event log ──────────────────────────────────────────────────────────────────────────────────────────────

create table public.events (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor text not null,
  entity text not null,
  entity_id text not null,
  action text not null,
  data jsonb
);
create index events_entity_idx on public.events (entity, entity_id);

create trigger events_append_only before update or delete on public.events
  for each row execute function public.forbid_change();

-- Records every insert and update on the tables below. Updates log only the columns that changed.
create function public.log_event() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  key text := tg_argv[0];
  changed jsonb;
begin
  if tg_op = 'INSERT' then
    insert into public.events (actor, entity, entity_id, action, data)
    values (public.current_actor(), tg_table_name, to_jsonb(new) ->> key, 'insert', to_jsonb(new));
  else
    select jsonb_object_agg(n.key, n.value) into changed
    from jsonb_each(to_jsonb(new)) n
    where n.key <> 'updated_at' and n.value is distinct from (to_jsonb(old) -> n.key);
    if changed is not null then
      insert into public.events (actor, entity, entity_id, action, data)
      values (public.current_actor(), tg_table_name, to_jsonb(new) ->> key, 'update', changed);
    end if;
  end if;
  return new;
end $$;

-- ── Catalogue: concepts ────────────────────────────────────────────────────────────────────────────────────

-- What a food is: sections at the top, then foods, then forms. Concepts never hold nutrition.
create table public.concepts (
  id text primary key check (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  kind text not null check (kind in ('section', 'food', 'form')),
  parent_id text references public.concepts (id),
  name text not null check (length(btrim(name)) > 0),
  synonyms text[] not null default '{}',
  image_id uuid,
  -- cnf:<code> or a record id; CNF records live in the app, so this is not a foreign key.
  default_record_id text check (default_record_id ~ '^(cnf:[0-9]+|gtin:[0-9]{14}|food:[a-z0-9-]+)$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((kind = 'section') = (parent_id is null)),
  check (parent_id is distinct from id)
);
create index concepts_parent_idx on public.concepts (parent_id);

-- One illustration per concept: generated clay art, never a product or brand. Bytes live in `concept-art`.
create table public.concept_images (
  id uuid primary key default gen_random_uuid(),
  concept_id text not null references public.concepts (id),
  object_path text not null unique,
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  alt text not null check (length(btrim(alt)) > 0),
  prompt text,
  origin text not null check (origin in ('generated', 'foodcards', 'original')),
  extraction_id uuid,
  created_at timestamptz not null default now()
);
alter table public.concepts add foreign key (image_id) references public.concept_images (id);

-- ── Intake: submissions and photos ─────────────────────────────────────────────────────────────────────────

create table public.submissions (
  id uuid primary key default gen_random_uuid(),
  owner uuid references auth.users (id) default auth.uid(),
  source text not null default 'app' check (source in ('app', 'admin', 'test')),
  raw_barcode text check (raw_barcode ~ '^[0-9]{6,14}$'),
  symbology text check (symbology in ('ean13', 'ean8', 'upca', 'upce', 'itf14', 'unknown')),
  gtin text check (gtin is null or public.gtin_valid(gtin)),
  -- The id the app logs against while this waits: gtin:<14 digits> for a barcode, pending:<uuid> otherwise.
  provisional_id text not null check (provisional_id ~ '^(gtin:[0-9]{14}|pending:[0-9a-f-]{36})$'),
  name_hint text,
  brand_hint text,
  note text,
  status text not null default 'uploading'
    check (status in ('uploading', 'queued', 'claimed', 'drafted', 'accepted', 'rejected')),
  claimed_by text,
  claimed_at timestamptz,
  record_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((gtin is null) = (raw_barcode is null)),
  check (gtin is null or provisional_id = 'gtin:' || gtin)
);
create index submissions_status_idx on public.submissions (status, created_at);
create index submissions_owner_idx on public.submissions (owner);

create table public.submission_photos (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.submissions (id),
  role text not null check (role in ('front', 'nutrition', 'ingredients', 'other')),
  -- In the private `label-photos` bucket: <owner or admin>/<submission>/<sha256>.<ext>
  object_path text not null unique,
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  content_type text not null check (content_type in ('image/jpeg', 'image/png', 'image/webp')),
  width int check (width > 0),
  height int check (height > 0),
  bytes int not null check (bytes > 0),
  created_at timestamptz not null default now()
);
create index submission_photos_submission_idx on public.submission_photos (submission_id);

-- ── Review: extractions and decisions ──────────────────────────────────────────────────────────────────────

-- One AI attempt at reading a submission. `payload` is the agent's structured output, `derived` the per-100 g
-- values and portions the admin computed from it, `checks` the automated validation results.
create table public.extractions (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.submissions (id),
  attempt int not null check (attempt > 0),
  agent text not null,
  model text,
  prompt_version text not null,
  thread_id text,
  payload jsonb not null,
  derived jsonb not null,
  checks jsonb not null,
  -- Generated art awaiting acceptance: { object_path, sha256, alt, prompt } in `concept-art`, or null.
  art jsonb,
  trace jsonb,
  created_at timestamptz not null default now(),
  unique (submission_id, attempt)
);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.submissions (id),
  extraction_id uuid not null unique references public.extractions (id),
  decision text not null check (decision in ('accept', 'reject')),
  reviewer text not null check (length(btrim(reviewer)) > 0),
  comment text,
  -- For an accept: what the reviewer changed relative to the extraction (JSON paths and values).
  edits jsonb,
  created_at timestamptz not null default now(),
  check (decision = 'accept' or length(btrim(coalesce(comment, ''))) > 0)
);

-- ── Catalogue: records ─────────────────────────────────────────────────────────────────────────────────────

create table public.records (
  id text primary key check (id ~ '^(gtin:[0-9]{14}|food:[a-z0-9]+(-[a-z0-9]+)*)$'),
  role text not null check (role in ('product', 'generic')),
  concept_id text not null references public.concepts (id),
  current_revision_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index records_concept_idx on public.records (concept_id);

-- Every accepted review produces a revision: the full record as published, traceable to its evidence.
create table public.record_revisions (
  id uuid primary key default gen_random_uuid(),
  record_id text not null references public.records (id),
  review_id uuid not null unique references public.reviews (id),
  extraction_id uuid not null references public.extractions (id),
  data jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.records add foreign key (current_revision_id) references public.record_revisions (id);
alter table public.submissions add foreign key (record_id) references public.records (id);
alter table public.concept_images add foreign key (extraction_id) references public.extractions (id);

-- Old id → current id: provisional ids, merged duplicates, repackaged products.
create table public.aliases (
  from_id text primary key,
  to_id text not null references public.records (id),
  review_id uuid references public.reviews (id),
  reason text not null,
  created_at timestamptz not null default now(),
  check (from_id <> to_id)
);

-- ── Triggers ───────────────────────────────────────────────────────────────────────────────────────────────

create trigger concepts_updated before update on public.concepts
  for each row execute function public.touch_updated_at();
create trigger submissions_updated before update on public.submissions
  for each row execute function public.touch_updated_at();
create trigger records_updated before update on public.records
  for each row execute function public.touch_updated_at();

create trigger concepts_no_delete before delete on public.concepts
  for each row execute function public.forbid_delete();
create trigger submissions_no_delete before delete on public.submissions
  for each row execute function public.forbid_delete();
create trigger records_no_delete before delete on public.records
  for each row execute function public.forbid_delete();

create trigger concept_images_append_only before update or delete on public.concept_images
  for each row execute function public.forbid_change();
create trigger submission_photos_append_only before update or delete on public.submission_photos
  for each row execute function public.forbid_change();
create trigger extractions_append_only before update or delete on public.extractions
  for each row execute function public.forbid_change();
create trigger reviews_append_only before update or delete on public.reviews
  for each row execute function public.forbid_change();
create trigger record_revisions_append_only before update or delete on public.record_revisions
  for each row execute function public.forbid_change();
create trigger aliases_append_only before update or delete on public.aliases
  for each row execute function public.forbid_change();

create trigger concepts_log after insert or update on public.concepts
  for each row execute function public.log_event('id');
create trigger concept_images_log after insert on public.concept_images
  for each row execute function public.log_event('id');
create trigger submissions_log after insert or update on public.submissions
  for each row execute function public.log_event('id');
create trigger submission_photos_log after insert on public.submission_photos
  for each row execute function public.log_event('id');
create trigger extractions_log after insert on public.extractions
  for each row execute function public.log_event('id');
create trigger reviews_log after insert on public.reviews
  for each row execute function public.log_event('id');
create trigger records_log after insert or update on public.records
  for each row execute function public.log_event('id');
create trigger record_revisions_log after insert on public.record_revisions
  for each row execute function public.log_event('id');
create trigger aliases_log after insert on public.aliases
  for each row execute function public.log_event('from_id');

-- ── Access: the app ────────────────────────────────────────────────────────────────────────────────────────

alter table public.events enable row level security;
alter table public.concepts enable row level security;
alter table public.concept_images enable row level security;
alter table public.submissions enable row level security;
alter table public.submission_photos enable row level security;
alter table public.extractions enable row level security;
alter table public.reviews enable row level security;
alter table public.records enable row level security;
alter table public.record_revisions enable row level security;
alter table public.aliases enable row level security;

revoke all on all tables in schema public from anon, authenticated;

-- The published catalogue is readable by the signed-in app.
grant select on public.concepts, public.concept_images, public.records, public.record_revisions, public.aliases
  to authenticated;
create policy concepts_read on public.concepts for select to authenticated using (true);
create policy concept_images_read on public.concept_images for select to authenticated using (true);
create policy records_read on public.records for select to authenticated using (true);
create policy record_revisions_read on public.record_revisions for select to authenticated using (true);
create policy aliases_read on public.aliases for select to authenticated using (true);

-- The app adds its own submissions and photos and can follow their progress.
grant select, insert on public.submissions, public.submission_photos to authenticated;
grant select on public.extractions, public.reviews to authenticated;

create policy submissions_read on public.submissions for select to authenticated
  using (owner = (select auth.uid()));
create policy submissions_add on public.submissions for insert to authenticated
  with check (owner = (select auth.uid()) and source = 'app' and status = 'uploading'
              and claimed_by is null and record_id is null);

create policy photos_read on public.submission_photos for select to authenticated
  using (exists (select 1 from public.submissions s
                 where s.id = submission_id and s.owner = (select auth.uid())));
create policy photos_add on public.submission_photos for insert to authenticated
  with check (
    split_part(object_path, '/', 1) = (select auth.uid())::text
    and split_part(object_path, '/', 2) = submission_id::text
    and exists (select 1 from public.submissions s
                where s.id = submission_id and s.owner = (select auth.uid()) and s.status = 'uploading'));

create policy extractions_read on public.extractions for select to authenticated
  using (exists (select 1 from public.submissions s
                 where s.id = submission_id and s.owner = (select auth.uid())));
create policy reviews_read on public.reviews for select to authenticated
  using (exists (select 1 from public.submissions s
                 where s.id = submission_id and s.owner = (select auth.uid())));

-- ── Storage ────────────────────────────────────────────────────────────────────────────────────────────────

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('label-photos', 'label-photos', false, 10485760, array['image/jpeg', 'image/png', 'image/webp']),
  ('concept-art', 'concept-art', true, 5242880, array['image/png', 'image/webp']);

-- Photos go under the uploader's own folder and are never replaced or removed (no update or delete policy).
create policy label_photos_add on storage.objects for insert to authenticated
  with check (bucket_id = 'label-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy label_photos_read on storage.objects for select to authenticated
  using (bucket_id = 'label-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ── Pipeline functions ─────────────────────────────────────────────────────────────────────────────────────

-- The app, after uploading every photo: hand the submission to the review queue.
create function public.queue_submission(p_submission uuid) returns public.submissions
language plpgsql security definer set search_path = '' as $$
declare
  s public.submissions;
begin
  select * into s from public.submissions where id = p_submission for update;
  if s.id is null or s.owner is distinct from (select auth.uid()) then
    raise exception 'submission % not found', p_submission using errcode = 'no_data_found';
  end if;
  if s.status <> 'uploading' then
    raise exception 'submission % is already %', p_submission, s.status using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.submission_photos where submission_id = p_submission) then
    raise exception 'add at least one photo before queueing' using errcode = 'check_violation';
  end if;
  update public.submissions set status = 'queued' where id = p_submission returning * into s;
  return s;
end $$;

-- The admin: name the actor for its own direct writes (admin and test submissions) in this transaction.
create function public.admin_set_actor(p_actor text) returns void
language sql set search_path = '' as $$
  select set_config('nutrimeter.actor', p_actor, true)
$$;

-- The agent: take a queued (or rejected, for another attempt) submission.
create function public.claim_submission(p_submission uuid, p_actor text) returns public.submissions
language plpgsql security definer set search_path = '' as $$
declare
  s public.submissions;
begin
  perform set_config('nutrimeter.actor', p_actor, true);
  update public.submissions
     set status = 'claimed', claimed_by = p_actor, claimed_at = now()
   where id = p_submission and status in ('queued', 'rejected', 'drafted')
  returning * into s;
  if s.id is null then
    raise exception 'submission % is not waiting for review', p_submission using errcode = 'check_violation';
  end if;
  return s;
end $$;

-- The agent: give a claim back without an extraction (the run failed or was cancelled).
create function public.release_submission(p_submission uuid, p_actor text, p_reason text) returns public.submissions
language plpgsql security definer set search_path = '' as $$
declare
  s public.submissions;
  previous text;
begin
  perform set_config('nutrimeter.actor', p_actor, true);
  select case
           when exists (select 1 from public.reviews r where r.submission_id = p_submission) and not exists (
             select 1 from public.extractions e where e.submission_id = p_submission
               and not exists (select 1 from public.reviews r where r.extraction_id = e.id))
           then 'rejected'
           when exists (select 1 from public.extractions e where e.submission_id = p_submission
               and not exists (select 1 from public.reviews r where r.extraction_id = e.id))
           then 'drafted'
           else 'queued'
         end into previous;
  update public.submissions set status = previous, claimed_by = null, claimed_at = null
   where id = p_submission and status = 'claimed'
  returning * into s;
  if s.id is null then
    raise exception 'submission % is not claimed', p_submission using errcode = 'check_violation';
  end if;
  insert into public.events (actor, entity, entity_id, action, data)
  values (p_actor, 'submissions', p_submission::text, 'release', jsonb_build_object('reason', p_reason));
  return s;
end $$;

-- The agent: store an attempt. The submission waits for a human review.
create function public.record_extraction(
  p_submission uuid, p_actor text, p_model text, p_prompt_version text, p_thread_id text,
  p_payload jsonb, p_derived jsonb, p_checks jsonb, p_art jsonb, p_trace jsonb
) returns public.extractions
language plpgsql security definer set search_path = '' as $$
declare
  e public.extractions;
begin
  perform set_config('nutrimeter.actor', p_actor, true);
  perform 1 from public.submissions where id = p_submission and status = 'claimed' for update;
  if not found then
    raise exception 'submission % is not claimed', p_submission using errcode = 'check_violation';
  end if;
  insert into public.extractions (submission_id, attempt, agent, model, prompt_version, thread_id,
                                  payload, derived, checks, art, trace)
  values (p_submission,
          coalesce((select max(attempt) from public.extractions where submission_id = p_submission), 0) + 1,
          p_actor, p_model, p_prompt_version, p_thread_id, p_payload, p_derived, p_checks, p_art, p_trace)
  returning * into e;
  update public.submissions set status = 'drafted', claimed_by = null, claimed_at = null where id = p_submission;
  return e;
end $$;

-- A human: reject an attempt with a reason. The submission goes back for another attempt.
create function public.reject_extraction(p_extraction uuid, p_reviewer text, p_comment text)
returns public.reviews
language plpgsql security definer set search_path = '' as $$
declare
  e public.extractions;
  r public.reviews;
begin
  perform set_config('nutrimeter.actor', 'reviewer:' || p_reviewer, true);
  select * into e from public.extractions where id = p_extraction;
  if e.id is null then
    raise exception 'extraction % not found', p_extraction using errcode = 'no_data_found';
  end if;
  perform 1 from public.submissions where id = e.submission_id and status = 'drafted' for update;
  if not found then
    raise exception 'submission % is not waiting for a decision', e.submission_id using errcode = 'check_violation';
  end if;
  if e.attempt <> (select max(attempt) from public.extractions where submission_id = e.submission_id) then
    raise exception 'only the latest attempt can be reviewed' using errcode = 'check_violation';
  end if;
  insert into public.reviews (submission_id, extraction_id, decision, reviewer, comment)
  values (e.submission_id, e.id, 'reject', p_reviewer, p_comment)
  returning * into r;
  update public.submissions set status = 'rejected' where id = e.submission_id;
  return r;
end $$;

-- A human: accept an attempt. In one transaction this records the review, creates the concept and its image
-- when they are new, creates or revises the record, aliases the provisional id, and closes the submission.
--
-- p_publish = {
--   record_id, role,
--   concept: { id, kind, parent_id, name, synonyms, is_new },
--   data: { …the record as published… },
--   art: { object_path, sha256, alt, prompt } | null,
--   set_default: bool          -- make this record the concept's default
-- }
create function public.accept_extraction(p_extraction uuid, p_reviewer text, p_comment text, p_edits jsonb,
                                         p_publish jsonb)
returns public.record_revisions
language plpgsql security definer set search_path = '' as $$
declare
  e public.extractions;
  s public.submissions;
  r public.reviews;
  rev public.record_revisions;
  c jsonb := p_publish -> 'concept';
  rec_id text := p_publish ->> 'record_id';
  img uuid;
begin
  perform set_config('nutrimeter.actor', 'reviewer:' || p_reviewer, true);
  select * into e from public.extractions where id = p_extraction;
  if e.id is null then
    raise exception 'extraction % not found', p_extraction using errcode = 'no_data_found';
  end if;
  select * into s from public.submissions where id = e.submission_id and status = 'drafted' for update;
  if s.id is null then
    raise exception 'submission % is not waiting for a decision', e.submission_id using errcode = 'check_violation';
  end if;
  if e.attempt <> (select max(attempt) from public.extractions where submission_id = e.submission_id) then
    raise exception 'only the latest attempt can be reviewed' using errcode = 'check_violation';
  end if;
  if s.gtin is not null and rec_id <> 'gtin:' || s.gtin
     and not exists (select 1 from public.records where id = rec_id) then
    raise exception 'a barcode submission publishes as gtin:% or merges into an existing record', s.gtin
      using errcode = 'check_violation';
  end if;

  insert into public.reviews (submission_id, extraction_id, decision, reviewer, comment, edits)
  values (s.id, e.id, 'accept', p_reviewer, p_comment, p_edits)
  returning * into r;

  if not exists (select 1 from public.concepts where id = c ->> 'id') then
    insert into public.concepts (id, kind, parent_id, name, synonyms)
    values (c ->> 'id', c ->> 'kind', c ->> 'parent_id', c ->> 'name',
            coalesce(array(select jsonb_array_elements_text(c -> 'synonyms')), '{}'));
  end if;

  if p_publish -> 'art' is not null and jsonb_typeof(p_publish -> 'art') = 'object'
     and (select image_id from public.concepts where id = c ->> 'id') is null then
    insert into public.concept_images (concept_id, object_path, sha256, alt, prompt, origin, extraction_id)
    values (c ->> 'id', p_publish -> 'art' ->> 'object_path', p_publish -> 'art' ->> 'sha256',
            p_publish -> 'art' ->> 'alt', p_publish -> 'art' ->> 'prompt', 'generated', e.id)
    returning id into img;
    update public.concepts set image_id = img where id = c ->> 'id';
  end if;

  insert into public.records (id, role, concept_id)
  values (rec_id, p_publish ->> 'role', c ->> 'id')
  on conflict (id) do update set concept_id = excluded.concept_id, role = excluded.role;

  insert into public.record_revisions (record_id, review_id, extraction_id, data)
  values (rec_id, r.id, e.id, p_publish -> 'data')
  returning * into rev;
  update public.records set current_revision_id = rev.id where id = rec_id;

  if coalesce((p_publish ->> 'set_default')::boolean, false) then
    update public.concepts set default_record_id = rec_id where id = c ->> 'id';
  end if;

  if s.provisional_id <> rec_id and not exists (select 1 from public.aliases where from_id = s.provisional_id) then
    insert into public.aliases (from_id, to_id, review_id, reason)
    values (s.provisional_id, rec_id, r.id, 'provisional');
  end if;

  update public.submissions set status = 'accepted', record_id = rec_id where id = s.id;
  return rev;
end $$;

-- ── Function access ────────────────────────────────────────────────────────────────────────────────────────

-- Supabase grants EXECUTE on new functions in public to anon and authenticated by default. Take it all back,
-- then give the app only what it needs. Everything else is for service_role (the local admin).
revoke all on all functions in schema public from public, anon, authenticated;
grant execute on function public.gtin_valid(text) to anon, authenticated;
grant execute on function public.queue_submission(uuid) to authenticated;
grant execute on all functions in schema public to service_role;

-- ── Seed: browse sections ──────────────────────────────────────────────────────────────────────────────────

insert into public.concepts (id, kind, name) values
  ('fruit', 'section', 'Fruit'),
  ('vegetables', 'section', 'Vegetables'),
  ('legumes', 'section', 'Legumes'),
  ('nuts-seeds', 'section', 'Nuts & seeds'),
  ('grains', 'section', 'Grains & cereals'),
  ('herbs-spices', 'section', 'Herbs & spices'),
  ('mushrooms', 'section', 'Mushrooms'),
  ('seaweeds', 'section', 'Seaweeds'),
  ('dairy', 'section', 'Dairy'),
  ('eggs', 'section', 'Eggs'),
  ('meat', 'section', 'Meat & poultry'),
  ('fish', 'section', 'Fish & seafood'),
  ('plant-based', 'section', 'Plant-based alternatives'),
  ('bakery', 'section', 'Bread & bakery'),
  ('snacks', 'section', 'Snacks & sweets'),
  ('spreads', 'section', 'Spreads, sauces & condiments'),
  ('oils-fats', 'section', 'Oils & fats'),
  ('drinks', 'section', 'Drinks'),
  ('meals', 'section', 'Meals & prepared foods');
