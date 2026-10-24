-- The taxonomy replaces concepts. Records are the catalogue; the taxonomy only indexes them.
--
--   food_groups → food_subgroups → food_categories      seeded from USDA WWEIA (next migration), fixed
--   records.category_id                                  null = uncategorized ("Other"); otherwise one category,
--                                                        which implies its subgroup and group
--
-- Images are cosmetic and belong to the taxonomy, never to records: a record shows its category's image, else its
-- subgroup's, else its group's. The AI may only pick an existing category; creating categories is a separate,
-- human-run process.

-- ── Concepts go ────────────────────────────────────────────────────────────────────────────────────────────

alter table public.records drop column concept_id;
drop table public.concept_images cascade;
drop table public.concepts cascade;

-- ── Taxonomy ───────────────────────────────────────────────────────────────────────────────────────────────

create table public.food_groups (
  id text primary key check (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name text not null check (length(btrim(name)) > 0),
  position int not null,
  source text not null,
  -- Cosmetic only, in the public `taxonomy-art` bucket.
  image_path text,
  image_alt text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.food_subgroups (
  id text primary key check (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  group_id text not null references public.food_groups (id),
  name text not null check (length(btrim(name)) > 0),
  position int not null,
  source text not null,
  image_path text,
  image_alt text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index food_subgroups_group_idx on public.food_subgroups (group_id);

create table public.food_categories (
  id text primary key check (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  subgroup_id text not null references public.food_subgroups (id),
  name text not null check (length(btrim(name)) > 0),
  position int not null,
  source text not null,
  note text,
  image_path text,
  image_alt text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index food_categories_subgroup_idx on public.food_categories (subgroup_id);

alter table public.records add column category_id text references public.food_categories (id);
create index records_category_idx on public.records (category_id);

create trigger food_groups_updated before update on public.food_groups
  for each row execute function public.touch_updated_at();
create trigger food_subgroups_updated before update on public.food_subgroups
  for each row execute function public.touch_updated_at();
create trigger food_categories_updated before update on public.food_categories
  for each row execute function public.touch_updated_at();
create trigger food_groups_no_delete before delete on public.food_groups
  for each row execute function public.forbid_delete();
create trigger food_subgroups_no_delete before delete on public.food_subgroups
  for each row execute function public.forbid_delete();
create trigger food_categories_no_delete before delete on public.food_categories
  for each row execute function public.forbid_delete();
create trigger food_groups_log after insert or update on public.food_groups
  for each row execute function public.log_event('id');
create trigger food_subgroups_log after insert or update on public.food_subgroups
  for each row execute function public.log_event('id');
create trigger food_categories_log after insert or update on public.food_categories
  for each row execute function public.log_event('id');

alter table public.food_groups enable row level security;
alter table public.food_subgroups enable row level security;
alter table public.food_categories enable row level security;
revoke all on public.food_groups, public.food_subgroups, public.food_categories from anon, authenticated;
grant select on public.food_groups, public.food_subgroups, public.food_categories to authenticated;
create policy food_groups_read on public.food_groups for select to authenticated using (true);
create policy food_subgroups_read on public.food_subgroups for select to authenticated using (true);
create policy food_categories_read on public.food_categories for select to authenticated using (true);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('taxonomy-art', 'taxonomy-art', true, 5242880, array['image/png', 'image/webp']);

-- ── Publishing ─────────────────────────────────────────────────────────────────────────────────────────────

drop function public.accept_extraction(uuid, text, text, jsonb, jsonb);

-- A human: accept an attempt. In one transaction this records the review, creates or revises the record (with
-- its category, or none), aliases the provisional id, and closes the submission.
--
-- p_publish = { record_id, role, category_id (or null), data: { …the record as published… } }
create function public.accept_extraction(p_extraction uuid, p_reviewer text, p_comment text, p_edits jsonb,
                                         p_publish jsonb)
returns public.record_revisions
language plpgsql security definer set search_path = '' as $$
declare
  e public.extractions;
  s public.submissions;
  r public.reviews;
  rev public.record_revisions;
  rec_id text := p_publish ->> 'record_id';
  cat text := nullif(p_publish ->> 'category_id', '');
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
  if cat is not null and not exists (select 1 from public.food_categories where id = cat) then
    raise exception 'category % does not exist; categories are only added by the taxonomy process', cat
      using errcode = 'foreign_key_violation';
  end if;

  insert into public.reviews (submission_id, extraction_id, decision, reviewer, comment, edits)
  values (s.id, e.id, 'accept', p_reviewer, p_comment, p_edits)
  returning * into r;

  insert into public.records (id, role, category_id)
  values (rec_id, p_publish ->> 'role', cat)
  on conflict (id) do update set category_id = excluded.category_id, role = excluded.role;

  insert into public.record_revisions (record_id, review_id, extraction_id, data)
  values (rec_id, r.id, e.id, p_publish -> 'data')
  returning * into rev;
  update public.records set current_revision_id = rev.id where id = rec_id;

  if s.provisional_id <> rec_id and not exists (select 1 from public.aliases where from_id = s.provisional_id) then
    insert into public.aliases (from_id, to_id, review_id, reason)
    values (s.provisional_id, rec_id, r.id, 'provisional');
  end if;

  update public.submissions set status = 'accepted', record_id = rec_id where id = s.id;
  return rev;
end $$;

-- A human: file a published record under another category, or none. Indexing only, so no new revision; the
-- change and its reason are in the event log.
create function public.set_record_category(p_record text, p_category text, p_reviewer text, p_reason text)
returns public.records
language plpgsql security definer set search_path = '' as $$
declare
  rec public.records;
begin
  perform set_config('nutrimeter.actor', 'reviewer:' || p_reviewer, true);
  if length(btrim(coalesce(p_reason, ''))) = 0 then
    raise exception 'say why the category changes' using errcode = 'check_violation';
  end if;
  update public.records set category_id = nullif(p_category, '') where id = p_record returning * into rec;
  if rec.id is null then
    raise exception 'record % not found', p_record using errcode = 'no_data_found';
  end if;
  insert into public.events (actor, entity, entity_id, action, data)
  values ('reviewer:' || p_reviewer, 'records', p_record, 'recategorize',
          jsonb_build_object('category_id', rec.category_id, 'reason', p_reason));
  return rec;
end $$;

revoke all on function public.accept_extraction(uuid, text, text, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.set_record_category(text, text, text, text) from public, anon, authenticated;
grant execute on function public.accept_extraction(uuid, text, text, jsonb, jsonb) to service_role;
grant execute on function public.set_record_category(text, text, text, text) to service_role;
