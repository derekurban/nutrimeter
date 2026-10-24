-- Records from an official source: the Canadian Nutrient File's generic foods, published as `cnf:<code>` records
-- without a review. Their evidence is the source itself (Health Canada, CNF 2026), not photos, so their revisions
-- carry `source = 'cnf'` instead of a review and an extraction. Reviewed revisions are unchanged: source 'review',
-- with both. Only the admin (service_role) can publish them, through publish_official_records, which logs every
-- insert with its actor like any other write.

alter table public.records drop constraint records_id_check;
alter table public.records add constraint records_id_check
  check (id ~ '^(gtin:[0-9]{14}|food:[a-z0-9]+(-[a-z0-9]+)*|cnf:[0-9]+)$');

alter table public.record_revisions add column source text not null default 'review' check (source in ('review', 'cnf'));
alter table public.record_revisions alter column review_id drop not null;
alter table public.record_revisions alter column extraction_id drop not null;
alter table public.record_revisions add constraint record_revisions_evidence
  check ((source = 'review') = (review_id is not null and extraction_id is not null));

-- Publishes official records: p_records is [{ id: 'cnf:<code>', category_id, data }]. A new id becomes a generic
-- record filed under category_id (or uncategorized); an existing one gets a new revision only when its data changed,
-- and keeps its category (re-filing is set_record_category's, with a reason). Returns how many were created, revised
-- and left unchanged.
create function public.publish_official_records(p_actor text, p_source text, p_records jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r jsonb;
  rec_id text;
  current_data jsonb;
  rev_id uuid;
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
    if jsonb_typeof(r -> 'data') is distinct from 'object' then
      raise exception 'record % has no data', rec_id using errcode = 'check_violation';
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

revoke all on function public.publish_official_records(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.publish_official_records(text, text, jsonb) to service_role;
