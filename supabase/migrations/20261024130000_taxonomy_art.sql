-- Illustrations for the taxonomy, and their review. Cosmetic only: a group, subgroup or category shows its
-- accepted illustration; records never carry one.
--
--   taxonomy_art      every generated (or copied) illustration, with the prompt, the agent and the decision.
--                     The files live in the public `taxonomy-art` bucket under art/<id>.webp (shown) and
--                     art/<id>.png (as generated); rejected ones stay for the audit trail.
--   accept → the node's image_path/image_alt point at it, and any other pending illustration for that node is
--   superseded. Only the admin (service role) calls these functions.

create table public.taxonomy_art (
  id uuid primary key,
  level text not null check (level in ('group', 'subgroup', 'category')),
  node_id text not null,
  batch_id uuid,
  subject text not null check (length(btrim(subject)) > 0),
  prompt text not null,
  alt text not null check (length(btrim(alt)) > 0),
  generator text not null,
  thread_id text,
  image_path text not null,
  original_path text not null,
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  width int not null,
  height int not null,
  -- Automatic checks on the file (transparency, square, clear edges): [{level, message}].
  checks jsonb not null default '[]',
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected', 'superseded')),
  reviewer text,
  comment text,
  decided_at timestamptz,
  created_by text not null,
  created_at timestamptz not null default now(),
  check ((status = 'pending') = (decided_at is null)),
  check (status <> 'rejected' or length(btrim(coalesce(comment, ''))) > 0)
);
create index taxonomy_art_node_idx on public.taxonomy_art (level, node_id, created_at desc);
create index taxonomy_art_pending_idx on public.taxonomy_art (status) where status = 'pending';

create trigger taxonomy_art_no_delete before delete on public.taxonomy_art
  for each row execute function public.forbid_delete();
create trigger taxonomy_art_log after insert or update on public.taxonomy_art
  for each row execute function public.log_event('id');

alter table public.taxonomy_art enable row level security;
revoke all on public.taxonomy_art from anon, authenticated;

create function public.taxonomy_node_exists(p_level text, p_node text) returns boolean
language sql stable set search_path = '' as $$
  select case p_level
    when 'group' then exists (select 1 from public.food_groups where id = p_node)
    when 'subgroup' then exists (select 1 from public.food_subgroups where id = p_node)
    when 'category' then exists (select 1 from public.food_categories where id = p_node)
    else false
  end
$$;

-- The agent (through the admin): record one illustration waiting for review. The files are uploaded first.
create function public.record_taxonomy_art(p_actor text, p_art jsonb)
returns public.taxonomy_art
language plpgsql security definer set search_path = '' as $$
declare
  a public.taxonomy_art;
begin
  perform set_config('nutrimeter.actor', p_actor, true);
  if not public.taxonomy_node_exists(p_art ->> 'level', p_art ->> 'node_id') then
    raise exception '% % does not exist', p_art ->> 'level', p_art ->> 'node_id' using errcode = 'foreign_key_violation';
  end if;
  insert into public.taxonomy_art (id, level, node_id, batch_id, subject, prompt, alt, generator, thread_id,
                                   image_path, original_path, sha256, width, height, checks, created_by)
  values ((p_art ->> 'id')::uuid, p_art ->> 'level', p_art ->> 'node_id', (p_art ->> 'batch_id')::uuid,
          p_art ->> 'subject', p_art ->> 'prompt', p_art ->> 'alt', p_art ->> 'generator', p_art ->> 'thread_id',
          p_art ->> 'image_path', p_art ->> 'original_path', p_art ->> 'sha256', (p_art ->> 'width')::int,
          (p_art ->> 'height')::int, coalesce(p_art -> 'checks', '[]'), p_actor)
  returning * into a;
  return a;
end $$;

-- A human: accept or reject a pending illustration. Accepting puts it on its node (with the alt text, which the
-- reviewer may correct) and supersedes the node's other pending illustrations.
create function public.decide_taxonomy_art(p_art uuid, p_decision text, p_reviewer text, p_comment text,
                                           p_alt text default null)
returns public.taxonomy_art
language plpgsql security definer set search_path = '' as $$
declare
  a public.taxonomy_art;
  v_alt text;
begin
  perform set_config('nutrimeter.actor', 'reviewer:' || p_reviewer, true);
  select * into a from public.taxonomy_art where id = p_art for update;
  if a.id is null then
    raise exception 'illustration % not found', p_art using errcode = 'no_data_found';
  end if;
  if a.status <> 'pending' then
    raise exception 'illustration % is already %', p_art, a.status using errcode = 'check_violation';
  end if;
  if p_decision = 'reject' then
    if length(btrim(coalesce(p_comment, ''))) = 0 then
      raise exception 'say why it is rejected; the next attempt reads this' using errcode = 'check_violation';
    end if;
    update public.taxonomy_art set status = 'rejected', reviewer = p_reviewer, comment = p_comment, decided_at = now()
     where id = p_art returning * into a;
    return a;
  elsif p_decision <> 'accept' then
    raise exception 'decision must be accept or reject' using errcode = 'check_violation';
  end if;

  v_alt := coalesce(nullif(btrim(p_alt), ''), a.alt);
  update public.taxonomy_art
     set status = 'accepted', reviewer = p_reviewer, comment = nullif(btrim(p_comment), ''), alt = v_alt, decided_at = now()
   where id = p_art returning * into a;
  update public.taxonomy_art set status = 'superseded', reviewer = p_reviewer, decided_at = now()
   where level = a.level and node_id = a.node_id and status = 'pending';
  if a.level = 'group' then
    update public.food_groups set image_path = a.image_path, image_alt = v_alt where id = a.node_id;
  elsif a.level = 'subgroup' then
    update public.food_subgroups set image_path = a.image_path, image_alt = v_alt where id = a.node_id;
  else
    update public.food_categories set image_path = a.image_path, image_alt = v_alt where id = a.node_id;
  end if;
  return a;
end $$;

-- A human: take an illustration off its node (the node falls back to its parent's). The illustration's row stays.
create function public.clear_taxonomy_image(p_level text, p_node text, p_reviewer text, p_reason text)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform set_config('nutrimeter.actor', 'reviewer:' || p_reviewer, true);
  if length(btrim(coalesce(p_reason, ''))) = 0 then
    raise exception 'say why the illustration comes off' using errcode = 'check_violation';
  end if;
  if not public.taxonomy_node_exists(p_level, p_node) then
    raise exception '% % does not exist', p_level, p_node using errcode = 'foreign_key_violation';
  end if;
  if p_level = 'group' then
    update public.food_groups set image_path = null, image_alt = null where id = p_node;
  elsif p_level = 'subgroup' then
    update public.food_subgroups set image_path = null, image_alt = null where id = p_node;
  else
    update public.food_categories set image_path = null, image_alt = null where id = p_node;
  end if;
  insert into public.events (actor, entity, entity_id, action, data)
  values ('reviewer:' || p_reviewer, 'food_' || case p_level when 'category' then 'categories' else p_level || 's' end,
          p_node, 'clear-image', jsonb_build_object('reason', p_reason));
end $$;

revoke all on function public.taxonomy_node_exists(text, text) from public, anon, authenticated;
revoke all on function public.record_taxonomy_art(text, jsonb) from public, anon, authenticated;
revoke all on function public.decide_taxonomy_art(uuid, text, text, text, text) from public, anon, authenticated;
revoke all on function public.clear_taxonomy_image(text, text, text, text) from public, anon, authenticated;
grant execute on function public.taxonomy_node_exists(text, text) to service_role;
grant execute on function public.record_taxonomy_art(text, jsonb) to service_role;
grant execute on function public.decide_taxonomy_art(uuid, text, text, text, text) to service_role;
grant execute on function public.clear_taxonomy_image(text, text, text, text) to service_role;
