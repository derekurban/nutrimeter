-- Records digitised from package photos: products whose label was transcribed and verified by the admin's digitise
-- pipeline (photos, a transcription, a second read, a verifier and deterministic checks), published without a
-- person's review when nothing disputed them. The photos, the readings and the checks live where the products were
-- digitised (dev); a revision here carries `source = 'digitised'` and, in its data, the extraction it came from
-- (data.source.extraction), like a CNF revision carries its source instead of a review and an extraction.
--
-- A record a person reviewed (its current revision's source is 'review') is never overwritten from here.

alter table public.record_revisions drop constraint record_revisions_source_check;
alter table public.record_revisions add constraint record_revisions_source_check check (source in ('review', 'cnf', 'digitised'));

-- Publishes digitised products: p_records is [{ id: 'gtin:<14 digits>', category_id, data }]. A new id becomes a
-- product record filed under category_id (or uncategorized); an existing one gets a new revision only when its data
-- changed and a person has not reviewed it. Returns how many were created, revised, left unchanged and kept (reviewed).
create function public.publish_digitised_records(p_actor text, p_records jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r jsonb;
  rec_id text;
  current_data jsonb;
  current_source text;
  rev_id uuid;
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
    if jsonb_typeof(r -> 'data') is distinct from 'object' then
      raise exception 'record % has no data', rec_id using errcode = 'check_violation';
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

revoke all on function public.publish_digitised_records(text, jsonb) from public, anon, authenticated;
grant execute on function public.publish_digitised_records(text, jsonb) to service_role;
