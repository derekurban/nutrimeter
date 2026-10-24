-- The admin adds a submission from photos dropped into the review site: insert, attach photos and queue in one
-- transaction, logged under the admin's actor. The photo objects are uploaded to `label-photos/admin/<id>/`
-- beforehand.
drop function public.admin_set_actor(text);

create function public.create_admin_submission(p_actor text, p_submission jsonb, p_photos jsonb)
returns public.submissions
language plpgsql security definer set search_path = '' as $$
declare
  s public.submissions;
  ph jsonb;
begin
  perform set_config('nutrimeter.actor', p_actor, true);
  insert into public.submissions (id, owner, source, status, raw_barcode, symbology, gtin, provisional_id,
                                  name_hint, brand_hint, note)
  values ((p_submission ->> 'id')::uuid, null, coalesce(p_submission ->> 'source', 'admin'), 'uploading',
          p_submission ->> 'raw_barcode', p_submission ->> 'symbology', p_submission ->> 'gtin',
          p_submission ->> 'provisional_id', p_submission ->> 'name_hint', p_submission ->> 'brand_hint',
          p_submission ->> 'note')
  returning * into s;
  if s.source not in ('admin', 'test') then
    raise exception 'admin submissions have source admin or test' using errcode = 'check_violation';
  end if;
  for ph in select * from jsonb_array_elements(p_photos) loop
    if split_part(ph ->> 'object_path', '/', 1) <> 'admin' or split_part(ph ->> 'object_path', '/', 2) <> s.id::text then
      raise exception 'admin photos live under admin/<submission>/' using errcode = 'check_violation';
    end if;
    insert into public.submission_photos (submission_id, role, object_path, sha256, content_type, width, height, bytes)
    values (s.id, ph ->> 'role', ph ->> 'object_path', ph ->> 'sha256', ph ->> 'content_type',
            (ph ->> 'width')::int, (ph ->> 'height')::int, (ph ->> 'bytes')::int);
  end loop;
  if not exists (select 1 from public.submission_photos where submission_id = s.id) then
    raise exception 'add at least one photo' using errcode = 'check_violation';
  end if;
  update public.submissions set status = 'queued' where id = s.id returning * into s;
  return s;
end $$;

revoke all on function public.create_admin_submission(text, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.create_admin_submission(text, jsonb, jsonb) to service_role;
