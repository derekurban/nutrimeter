-- The app's catalogue sync, at the catalogue's size (some 17,000 records). Reading every record's whole current
-- revision came to about 40 MB in 170 requests, on every launch. catalogue_changes returns, a page at a time, the
-- records changed since the app last synced, each with only what the app reads from its data: about a fifth of it.
--
-- records.updated_at moves whenever a record is published, revised, refiled or unpublished (records_updated), so it
-- is the sync's cursor. Pages go in (updated_at, id) order; the app asks again from the last row it got.

create index records_updated_at_idx on public.records (updated_at, id);

-- What the app reads from a revision's data: names, the brand, barcodes, and each profile's id, values per 100 g and
-- portions (label and grams). Nulls are left out. Null for null.
create function public.app_record_data(d jsonb)
returns jsonb
language sql immutable set search_path = '' as $$
  select case when d is null then null else jsonb_strip_nulls(jsonb_build_object(
    'name', d -> 'name',
    'brand', d -> 'brand',
    'name_fr', d -> 'name_fr',
    'default_profile', d -> 'default_profile',
    'barcodes', (
      select jsonb_agg(jsonb_build_object('gtin', b.v -> 'gtin') order by b.n)
        from jsonb_array_elements(case jsonb_typeof(d -> 'barcodes') when 'array' then d -> 'barcodes' else '[]' end)
             with ordinality as b (v, n)),
    'profiles', (
      select jsonb_agg(jsonb_build_object(
               'id', p.v -> 'id',
               'per_100g', p.v -> 'per_100g',
               'portions', (
                 select jsonb_agg(jsonb_build_object('label', q.v -> 'label', 'grams', q.v -> 'grams') order by q.n)
                   from jsonb_array_elements(case jsonb_typeof(p.v -> 'portions') when 'array' then p.v -> 'portions' else '[]' end)
                        with ordinality as q (v, n))
             ) order by p.n)
        from jsonb_array_elements(case jsonb_typeof(d -> 'profiles') when 'array' then d -> 'profiles' else '[]' end)
             with ordinality as p (v, n))
  )) end
$$;

-- Records changed after (p_after, p_after_id), oldest change first, at most p_limit (up to 2000). data is null for a
-- record that is no longer published. With p_published_only (a first sync), only published records.
create function public.catalogue_changes(
  p_after timestamptz default null,
  p_after_id text default null,
  p_published_only boolean default false,
  p_limit int default 1000
)
returns table (id text, role text, category_id text, updated_at timestamptz, data jsonb)
language sql stable security invoker set search_path = '' as $$
  select r.id, r.role, r.category_id, r.updated_at, public.app_record_data(rv.data)
    from public.records r
    left join public.record_revisions rv on rv.id = r.current_revision_id
   where (p_after is null or (r.updated_at, r.id) > (p_after, coalesce(p_after_id, '')))
     and (not p_published_only or r.current_revision_id is not null)
   order by r.updated_at, r.id
   limit least(greatest(coalesce(p_limit, 1000), 1), 2000)
$$;

revoke all on function public.app_record_data(jsonb) from public, anon, authenticated;
revoke all on function public.catalogue_changes(timestamptz, text, boolean, int) from public, anon, authenticated;
grant execute on function public.app_record_data(jsonb) to authenticated, service_role;
grant execute on function public.catalogue_changes(timestamptz, text, boolean, int) to authenticated, service_role;
