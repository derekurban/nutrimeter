-- Record schema 3: one shape for every published record's data, whoever writes it (docs/food-model/record-schema.md,
-- record.schema.json). record_problems checks a record's data against it: the database half of the contract, beside
-- the JSON Schema each writer's tests use. The publish functions refuse data with problems:
-- publish_official_records (CNF) and publish_digitised_records always, and publish_device_review for schema 3. The
-- phone's version 0.4.0 still publishes schema 2, and that stays accepted until the app writes schema 3.

-- What is wrong with a record's data, one short sentence each; empty when it is a valid schema-3 record the app can
-- use. p_id is the record id: a cnf: record is a generic food from the CNF, any other a product read from its label.
create function public.record_problems(p_id text, d jsonb)
returns text[]
language plpgsql immutable set search_path = '' as $$
declare
  out text[] := '{}';
  generic boolean := p_id like 'cnf:%';
  nutrient_keys constant text[] := array['energy', 'caffeine', 'carbs', 'fiber', 'starch', 'sugars', 'addedSugars', 'fat',
    'satFat', 'monoFat', 'polyFat', 'omega3', 'omega6', 'transFat', 'cholesterol', 'protein', 'vitA', 'vitB1', 'vitB2',
    'vitB3', 'vitB5', 'vitB6', 'vitB12', 'biotin', 'folate', 'vitC', 'vitD', 'vitE', 'vitK', 'calcium', 'copper', 'iron',
    'magnesium', 'manganese', 'phosphorus', 'potassium', 'selenium', 'sodium', 'zinc'];
  k text;
  v jsonb;
  prof jsonb;
  por jsonb;
  main jsonb;
  pid text;
  ids text[] := '{}';
  labels text[];
  label text;
begin
  if jsonb_typeof(d) is distinct from 'object' then
    return array['the data is not an object'];
  end if;
  if d -> 'schema' is distinct from '3'::jsonb then
    return array[format('schema is %s, not 3', coalesce(d ->> 'schema', 'missing'))];
  end if;
  foreach k in array array['name', 'name_fr', 'brand', 'descriptor', 'qualifiers', 'barcodes', 'package', 'ingredients',
                           'claims', 'default_profile', 'profiles', 'source'] loop
    if not d ? k then
      out := out || format('%s is missing', k);
    end if;
  end loop;
  if jsonb_typeof(d -> 'name') is distinct from 'string' or btrim(d ->> 'name') = '' then
    out := out || 'it has no name'::text;
  end if;
  if (d -> 'source' ->> 'kind') is distinct from (case when generic then 'cnf' else 'label' end) then
    out := out || format('a %s record has a %s source', case when generic then 'cnf' else 'product' end,
                         coalesce(d -> 'source' ->> 'kind', 'missing'));
  end if;

  if jsonb_typeof(d -> 'profiles') is distinct from 'array' or jsonb_array_length(d -> 'profiles') = 0 then
    return out || 'it has no profiles'::text;
  end if;
  for prof in select x.value from jsonb_array_elements(d -> 'profiles') as x (value) loop
    pid := prof ->> 'id';
    if pid is null or pid not in ('as-sold', 'prepared', 'drained') then
      out := out || format('a profile has the id %s', coalesce(pid, 'null'));
    elsif pid = any (ids) then
      out := out || format('two profiles are %s', pid);
    end if;
    ids := ids || pid;
    if pid = d ->> 'default_profile' then
      main := prof;
    end if;

    if jsonb_typeof(prof -> 'per_100g') is distinct from 'object' then
      out := out || format('%s has no per_100g', pid);
    else
      for k, v in select e.key, e.value from jsonb_each(prof -> 'per_100g') as e loop
        if not k = any (nutrient_keys) then
          out := out || format('%s: %s is not a nutrient', pid, k);
        elsif jsonb_typeof(v) is distinct from 'number' or (v #>> '{}')::numeric < 0 then
          out := out || format('%s: %s per 100 g is not a number of 0 or more', pid, k);
        end if;
      end loop;
    end if;

    labels := '{}';
    if jsonb_typeof(prof -> 'portions') is distinct from 'array' then
      out := out || format('%s has no portions list', pid);
    else
      for por in select x.value from jsonb_array_elements(prof -> 'portions') as x (value) loop
        label := btrim(coalesce(por ->> 'label', ''));
        if label = '' or label in ('g', 'oz') then
          out := out || format('%s: a portion is labelled "%s"', pid, label);
        elsif label = any (labels) then
          out := out || format('%s: two portions are "%s"', pid, label);
        end if;
        labels := labels || label;
        if jsonb_typeof(por -> 'grams') is distinct from 'number' or (por ->> 'grams')::numeric <= 0 then
          out := out || format('%s: "%s" has no grams', pid, label);
        end if;
        if (por ->> 'grams_from') is null or (por ->> 'grams_from') not in ('label', 'density', 'package', 'source') then
          out := out || format('%s: "%s" does not say where its grams came from', pid, label);
        elsif (por ->> 'grams_from') = 'density' and jsonb_typeof(prof -> 'density') is distinct from 'object' then
          out := out || format('%s: "%s" has grams from millilitres without a density', pid, label);
        end if;
      end loop;
    end if;

    if generic and jsonb_typeof(prof -> 'printed') is distinct from 'null' then
      out := out || format('%s: a cnf record has no printed label', pid);
    elsif not generic and jsonb_typeof(prof -> 'printed') is distinct from 'object' then
      out := out || format('%s: a product keeps its label as printed', pid);
    end if;
  end loop;

  if main is null then
    out := out || format('the default profile %s is not one of its profiles', coalesce(d ->> 'default_profile', 'null'));
  else
    if jsonb_typeof(main -> 'per_100g' -> 'energy') is distinct from 'number' then
      out := out || 'the default profile has no energy per 100 g'::text;
    end if;
    if not generic and coalesce(jsonb_array_length(case jsonb_typeof(main -> 'portions') when 'array' then main -> 'portions' end), 0) = 0 then
      out := out || 'the default profile has no portion with grams'::text;
    end if;
  end if;

  if jsonb_typeof(d -> 'barcodes') is distinct from 'array' then
    out := out || 'barcodes is not a list'::text;
  else
    for v in select x.value from jsonb_array_elements(d -> 'barcodes') as x (value) loop
      if not public.gtin_valid(coalesce(v ->> 'gtin', '')) then
        out := out || format('%s is not a valid GTIN', coalesce(v ->> 'gtin', 'null'));
      end if;
    end loop;
    if p_id like 'gtin:%' and not exists (
      select 1 from jsonb_array_elements(d -> 'barcodes') as x (value) where 'gtin:' || (x.value ->> 'gtin') = p_id) then
      out := out || 'its barcodes do not include its id'::text;
    end if;
  end if;
  return out;
end $$;

revoke all on function public.record_problems(text, jsonb) from public, anon;
grant execute on function public.record_problems(text, jsonb) to authenticated, service_role;

-- publish_official_records, as in 20261025000000_official_records.sql, refusing data off the record schema.
create or replace function public.publish_official_records(p_actor text, p_source text, p_records jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r jsonb;
  rec_id text;
  current_data jsonb;
  rev_id uuid;
  problems text[];
  created int := 0;
  revised int := 0;
  unchanged int := 0;
begin
  if p_source is distinct from 'cnf' then
    raise exception 'unknown official source %', p_source using errcode = 'check_violation';
  end if;
  perform set_config('nutrimeter.actor', p_actor, true);
  for r in select * from jsonb_array_elements(p_records) loop
    rec_id := r ->> 'id';
    if rec_id is null or rec_id !~ '^cnf:[0-9]+$' then
      raise exception 'records from the Canadian Nutrient File have cnf:<code> ids, not %', rec_id
        using errcode = 'check_violation';
    end if;
    problems := public.record_problems(rec_id, r -> 'data');
    if cardinality(problems) > 0 then
      raise exception 'record % is off the record schema: %', rec_id, array_to_string(problems, '; ')
        using errcode = 'check_violation';
    end if;
    if exists (select 1 from public.records where id = rec_id) then
      select rv.data into current_data
        from public.records x join public.record_revisions rv on rv.id = x.current_revision_id
       where x.id = rec_id;
      if current_data = r -> 'data' then
        unchanged := unchanged + 1;
        continue;
      end if;
      revised := revised + 1;
    else
      insert into public.records (id, role, category_id) values (rec_id, 'generic', nullif(r ->> 'category_id', ''));
      created := created + 1;
    end if;
    insert into public.record_revisions (record_id, source, data) values (rec_id, p_source, r -> 'data')
      returning id into rev_id;
    update public.records set current_revision_id = rev_id where id = rec_id;
  end loop;
  return jsonb_build_object('created', created, 'revised', revised, 'unchanged', unchanged);
end $$;

-- publish_digitised_records, as in 20261101000000_digitised_records.sql, refusing data off the record schema.
create or replace function public.publish_digitised_records(p_actor text, p_records jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r jsonb;
  rec_id text;
  current_data jsonb;
  current_source text;
  rev_id uuid;
  problems text[];
  created int := 0;
  revised int := 0;
  unchanged int := 0;
  kept int := 0;
begin
  perform set_config('nutrimeter.actor', p_actor, true);
  for r in select * from jsonb_array_elements(p_records) loop
    rec_id := r ->> 'id';
    if rec_id is null or rec_id !~ '^gtin:[0-9]{14}$' then
      raise exception 'digitised products have gtin:<14 digits> ids, not %', rec_id using errcode = 'check_violation';
    end if;
    problems := public.record_problems(rec_id, r -> 'data');
    if cardinality(problems) > 0 then
      raise exception 'record % is off the record schema: %', rec_id, array_to_string(problems, '; ')
        using errcode = 'check_violation';
    end if;
    if exists (select 1 from public.records where id = rec_id) then
      select rv.data, rv.source into current_data, current_source
        from public.records x left join public.record_revisions rv on rv.id = x.current_revision_id
       where x.id = rec_id;
      if current_source = 'review' then
        kept := kept + 1;
        continue;
      end if;
      if current_data = r -> 'data' then
        unchanged := unchanged + 1;
        continue;
      end if;
      revised := revised + 1;
    else
      insert into public.records (id, role, category_id) values (rec_id, 'product', nullif(r ->> 'category_id', ''));
      created := created + 1;
    end if;
    insert into public.record_revisions (record_id, source, data) values (rec_id, 'digitised', r -> 'data')
      returning id into rev_id;
    update public.records set current_revision_id = rev_id where id = rec_id;
  end loop;
  return jsonb_build_object('created', created, 'revised', revised, 'unchanged', unchanged, 'kept', kept);
end $$;

-- publish_device_review, as in 20261107120000_device_reviews.sql, checking a schema-3 record whole.
create or replace function public.publish_device_review(
  p_submission uuid,
  p_agent text,
  p_model text,
  p_prompt_version text,
  p_payload jsonb,
  p_derived jsonb,
  p_checks jsonb,
  p_trace jsonb,
  p_edits jsonb,
  p_publish jsonb
) returns public.record_revisions
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
  s public.submissions;
  e public.extractions;
  r public.reviews;
  rev public.record_revisions;
  rec_id text := p_publish ->> 'record_id';
  cat text := nullif(p_publish ->> 'category_id', '');
  d jsonb := p_publish -> 'data';
  prof jsonb;
  problems text[];
begin
  if uid is null then
    raise exception 'sign in to publish a review' using errcode = 'insufficient_privilege';
  end if;
  perform set_config('nutrimeter.actor', 'user:' || uid::text, true);

  select * into s from public.submissions where id = p_submission for update;
  if s.id is null or s.owner is distinct from uid then
    raise exception 'submission % not found', p_submission using errcode = 'no_data_found';
  end if;

  -- A retry of a publish that already went through.
  if s.status = 'accepted' then
    select rv.* into rev
      from public.reviews rw join public.record_revisions rv on rv.review_id = rw.id
     where rw.submission_id = s.id and rw.decision = 'accept'
     order by rw.created_at desc limit 1;
    if rev.id is not null then
      return rev;
    end if;
  end if;
  if s.status <> 'uploading' then
    raise exception 'submission % is already %; only one still on the phone can be published from it', p_submission, s.status
      using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.submission_photos where submission_id = s.id) then
    raise exception 'upload the photos before publishing' using errcode = 'check_violation';
  end if;

  if coalesce(p_agent, '') !~ '^device:[a-z]+/[A-Za-z0-9._:-]+' then
    raise exception 'the agent is device:<provider>/<model>, not %', p_agent using errcode = 'check_violation';
  end if;
  if rec_id is null or rec_id !~ '^(gtin:[0-9]{14}|food:[a-z0-9]+(-[a-z0-9]+)*)$' then
    raise exception 'record id % is not a product id', rec_id using errcode = 'check_violation';
  end if;
  if s.gtin is not null and rec_id <> 'gtin:' || s.gtin then
    raise exception 'a barcode submission publishes as gtin:%', s.gtin using errcode = 'check_violation';
  end if;
  if cat is not null and not exists (select 1 from public.food_categories where id = cat) then
    raise exception 'category % does not exist; categories are only added by the taxonomy process', cat
      using errcode = 'foreign_key_violation';
  end if;

  -- Schema 3 is checked whole; schema 2 (the app's version 0.4.0) by the checks below until the app writes 3.
  if d -> 'schema' = '3'::jsonb then
    problems := public.record_problems(rec_id, d);
    if cardinality(problems) > 0 then
      raise exception 'the record is off the record schema: %', array_to_string(problems, '; ') using errcode = 'check_violation';
    end if;
  end if;

  -- The app must be able to use what it publishes.
  if jsonb_typeof(d) is distinct from 'object' or length(btrim(coalesce(d ->> 'name', ''))) = 0 then
    raise exception 'the record has no name' using errcode = 'check_violation';
  end if;
  select x.value into prof
    from jsonb_array_elements(case jsonb_typeof(d -> 'profiles') when 'array' then d -> 'profiles' else '[]' end) as x (value)
   order by (x.value ->> 'id' = d ->> 'default_profile') desc
   limit 1;
  if prof is null or jsonb_typeof(prof -> 'per_100g' -> 'energy') is distinct from 'number' then
    raise exception 'the record has no energy per 100 g' using errcode = 'check_violation';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(case jsonb_typeof(prof -> 'portions') when 'array' then prof -> 'portions' else '[]' end) as q (value)
     where jsonb_typeof(q.value -> 'grams') = 'number' and (q.value ->> 'grams')::numeric > 0) then
    raise exception 'the record has no portion with grams' using errcode = 'check_violation';
  end if;

  insert into public.extractions (submission_id, attempt, agent, model, prompt_version, thread_id,
                                  payload, derived, checks, art, trace)
  values (s.id,
          coalesce((select max(attempt) from public.extractions where submission_id = s.id), 0) + 1,
          p_agent, p_model, p_prompt_version, null, p_payload, coalesce(p_derived, '{}'::jsonb),
          coalesce(p_checks, '[]'::jsonb), null, p_trace)
  returning * into e;

  insert into public.reviews (submission_id, extraction_id, decision, reviewer, comment, edits)
  values (s.id, e.id, 'accept', 'user:' || uid::text, 'Reviewed on the phone', p_edits)
  returning * into r;

  insert into public.records (id, role, category_id)
  values (rec_id, 'product', cat)
  on conflict (id) do update set category_id = excluded.category_id, role = excluded.role;

  insert into public.record_revisions (record_id, review_id, extraction_id, data, source)
  values (rec_id, r.id, e.id, d, 'review')
  returning * into rev;
  update public.records set current_revision_id = rev.id where id = rec_id;

  if s.provisional_id <> rec_id and not exists (select 1 from public.aliases where from_id = s.provisional_id) then
    insert into public.aliases (from_id, to_id, review_id, reason)
    values (s.provisional_id, rec_id, r.id, 'provisional');
  end if;

  update public.submissions set status = 'accepted', record_id = rec_id where id = s.id;
  return rev;
end $$;
