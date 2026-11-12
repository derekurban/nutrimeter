-- The desktop review queue is retired (2026-11-12): products reach the catalogue through the phone's label review
-- (publish_device_review), and the admin's digitised products through publish_digitised_records. Submissions still
-- waiting in the queue are closed rather than deleted (evidence is never deleted): `closed` means no longer waiting
-- for a review. The submission keeps its photos and readings, and links the record published from it, if any; why it
-- was closed is in the event log. A closed submission can't be claimed, queued or published again.

alter table public.submissions drop constraint submissions_status_check;
alter table public.submissions add constraint submissions_status_check
  check (status in ('uploading', 'queued', 'claimed', 'drafted', 'accepted', 'rejected', 'closed'));

-- Closes waiting submissions: p_items is [{ id, record_id (or null), reason }]. Only a submission still waiting
-- (queued, claimed, drafted or rejected) is closed; a record_id links the record published from it. Returns how
-- many were closed and how many were not waiting.
create function public.close_submissions(p_actor text, p_items jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  item jsonb;
  closed int := 0;
  skipped int := 0;
  rec text;
begin
  perform set_config('nutrimeter.actor', p_actor, true);
  for item in select * from jsonb_array_elements(p_items) loop
    if length(btrim(coalesce(item ->> 'reason', ''))) = 0 then
      raise exception 'say why submission % is closed', item ->> 'id' using errcode = 'check_violation';
    end if;
    rec := nullif(item ->> 'record_id', '');
    update public.submissions
       set status = 'closed', claimed_by = null, claimed_at = null, record_id = coalesce(rec, record_id)
     where id = (item ->> 'id')::uuid and status in ('queued', 'claimed', 'drafted', 'rejected');
    if not found then
      skipped := skipped + 1;
      continue;
    end if;
    insert into public.events (actor, entity, entity_id, action, data)
    values (p_actor, 'submissions', item ->> 'id', 'close', jsonb_build_object('reason', item ->> 'reason', 'record_id', rec));
    closed := closed + 1;
  end loop;
  return jsonb_build_object('closed', closed, 'skipped', skipped);
end $$;

revoke all on function public.close_submissions(text, jsonb) from public, anon, authenticated;
grant execute on function public.close_submissions(text, jsonb) to service_role;
