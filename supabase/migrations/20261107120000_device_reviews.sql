-- Reviews done on the phone. The app reads a product's label with the signed-in person's own AI key (a first read,
-- an independent second read, deterministic checks, and a stronger verifier for the lines in doubt), the person
-- settles what is left against the photos, and the app publishes the result. The evidence is the same as for a desktop
-- review: the submission and its photos (uploaded by the app as usual, but never queued), an extraction holding the
-- readings and checks, an accepting review naming the person, a revision and an alias from the provisional id.
--
-- Only the owner of a submission can publish it, only while it is still uploading (never queued for the desktop),
-- and only a record the app can use: a name, energy per 100 g and a portion with grams. A retry after a lost answer
-- returns the revision already published instead of failing.

create function public.publish_device_review(
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

revoke all on function public.publish_device_review(uuid, text, text, text, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.publish_device_review(uuid, text, text, text, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb)
  to authenticated, service_role;
