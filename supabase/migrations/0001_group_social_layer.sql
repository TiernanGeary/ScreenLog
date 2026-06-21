-- Friend groups: social layer (SP1). Apply in the Supabase SQL editor.
-- Assumes existing tables: public.profiles(id uuid pk references auth.users).

create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  mode text not null check (mode in ('per_member','pool')),
  owner_time_zone text not null default 'UTC',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('owner','member')),
  joined_at timestamptz not null default now(),
  configured_at timestamptz,
  left_at timestamptz,
  removed_by uuid,
  primary key (group_id, user_id)
);

create table if not exists public.group_config (
  group_id uuid primary key references public.groups(id) on delete cascade,
  app_names text[] not null default '{}',
  per_member_limit_seconds int,
  pool_seconds int,
  reset text not null default 'daily' check (reset = 'daily'),
  approvals_required int not null default 1 check (approvals_required >= 1),
  updated_at timestamptz not null default now()
);

create table if not exists public.group_invites (
  code text primary key,
  group_id uuid not null references public.groups(id) on delete cascade,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_config enable row level security;
alter table public.group_invites enable row level security;

-- Helper: is the current user an active member of a group?
create or replace function public.is_group_member(p_group_id uuid)
returns boolean language sql security definer stable set search_path = public, pg_temp as $$
  select exists (
    -- Active = not left AND not owner-removed. Gating on left_at alone let a row
    -- left in the (left_at null, removed_by set) state by a redeem/remove race be
    -- treated as active; removed_by null closes that regardless of timing.
    select 1 from public.group_members m
    where m.group_id = p_group_id and m.user_id = auth.uid()
      and m.left_at is null and m.removed_by is null
  );
$$;

create policy groups_select on public.groups for select
  using (public.is_group_member(id));
create policy group_members_select on public.group_members for select
  using (public.is_group_member(group_id));
create policy group_config_select on public.group_config for select
  using (public.is_group_member(group_id));
-- All writes go through SECURITY DEFINER RPCs below; no direct write policies.

-- 8-char A–Z2–9 code (no ambiguous chars).
-- pgcrypto's gen_random_bytes lives in the `extensions` schema on Supabase; the
-- definer callers pin search_path to public, pg_temp, so widen it here (a missing
-- `extensions` schema is silently ignored, so this is safe everywhere).
create or replace function public.gen_group_code() returns text language sql
  set search_path = public, extensions, pg_temp as $$
  with alphabet(chars) as (values ('ABCDEFGHJKLMNPQRSTUVWXYZ23456789'::text)),
       bytes(data) as (select gen_random_bytes(8))
  select string_agg(substr(alphabet.chars,
      (get_byte(bytes.data, gs.i) % length(alphabet.chars)) + 1, 1), '' order by gs.i)
  from alphabet, bytes, generate_series(0,7) as gs(i);
$$;

create or replace function public.create_group(
  p_name text, p_mode text, p_app_names text[],
  p_limit_seconds int, p_approvals_required int, p_owner_time_zone text)
returns table(group_id uuid, code text)
language plpgsql security definer set search_path = public, pg_temp as $$
declare g_id uuid; inv_code text; owner_tz text;
begin
  if auth.uid() is null then raise exception 'auth required'; end if;
  -- Require a positive limit so a group can never land with a null/0 pool or
  -- per-member limit that the client would silently clamp up to the 5-min minimum.
  if coalesce(p_limit_seconds, 0) <= 0 then raise exception 'limit required'; end if;
  owner_tz := coalesce(p_owner_time_zone, 'UTC');
  begin
    perform now() at time zone owner_tz;
  exception when others then
    owner_tz := 'UTC';
  end;
  insert into public.groups(owner_id, name, mode, owner_time_zone)
    values (auth.uid(), p_name, p_mode, owner_tz)
    returning id into g_id;
  insert into public.group_members(group_id, user_id, role) values (g_id, auth.uid(), 'owner');
  insert into public.group_config(group_id, app_names,
      per_member_limit_seconds, pool_seconds, approvals_required)
    values (g_id, coalesce(p_app_names,'{}'),
      case when p_mode='per_member' then p_limit_seconds end,
      case when p_mode='pool' then p_limit_seconds end,
      greatest(coalesce(p_approvals_required,1),1));
  loop
    begin
      inv_code := public.gen_group_code();
      insert into public.group_invites(code, group_id, created_by, expires_at)
        values (inv_code, g_id, auth.uid(), now() + interval '30 days');
      exit;
    exception when unique_violation then
      continue;
    end;
  end loop;
  return query select g_id, inv_code;
end; $$;

create or replace function public.create_group_invite(p_group_id uuid)
returns table(code text, expires_at timestamptz)
language plpgsql security definer set search_path = public, pg_temp as $$
declare inv_code text; exp timestamptz;
begin
  if not exists (select 1 from public.groups where id=p_group_id and owner_id=auth.uid())
    then raise exception 'owner only'; end if;
  exp := now() + interval '30 days';
  loop
    begin
      inv_code := public.gen_group_code();
      insert into public.group_invites(code, group_id, created_by, expires_at)
        values (inv_code, p_group_id, auth.uid(), exp);
      exit;
    exception when unique_violation then
      continue;
    end;
  end loop;
  return query select inv_code, exp;
end; $$;

create or replace function public.peek_group_invite(p_code text)
returns table(group_id uuid, group_name text, owner_display_name text, mode text)
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  return query
  select g.id, g.name, p.display_name, g.mode
  from public.group_invites i
  join public.groups g on g.id=i.group_id
  join public.profiles p on p.id=g.owner_id
  where i.code = upper(p_code) and i.expires_at > now();
end; $$;

create or replace function public.redeem_group_invite(p_code text)
returns table(group_id uuid, group_name text)
language plpgsql security definer set search_path = public, pg_temp as $$
declare g_id uuid; g_name text; existing_removed_by uuid;
begin
  if auth.uid() is null then raise exception 'auth required'; end if;
  select i.group_id, g.name into g_id, g_name
    from public.group_invites i join public.groups g on g.id=i.group_id
    where i.code = upper(p_code) and i.expires_at > now();
  if g_id is null then raise exception 'invalid or expired code'; end if;
  -- Lock the existing membership row so a concurrent remove_group_member can't
  -- slip between this check and the upsert below and get its removal clobbered.
  select m.removed_by into existing_removed_by
    from public.group_members m
    where m.group_id = g_id and m.user_id = auth.uid()
    for update;
  if existing_removed_by is not null then raise exception 'removed from group'; end if;
  insert into public.group_members(group_id, user_id, role)
    values (g_id, auth.uid(), 'member')
    -- Never resurrect a removed row: only clear left_at when not owner-removed.
    on conflict (group_id, user_id) do update set left_at = null, configured_at = null
      where group_members.removed_by is null;  -- idempotent / rejoin
  return query select g_id, g_name;
end; $$;

create or replace function public.get_my_groups()
returns table(id uuid, name text, mode text, owner_id uuid, owner_time_zone text,
  role text, configured_at timestamptz, member_count int,
  app_names text[], per_member_limit_seconds int, pool_seconds int,
  approvals_required int, updated_at timestamptz)
language plpgsql security definer stable set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  return query
  select g.id, g.name, g.mode, g.owner_id, g.owner_time_zone,
    m.role, m.configured_at,
    (select count(*) from public.group_members mm where mm.group_id=g.id and mm.left_at is null)::int,
    c.app_names, c.per_member_limit_seconds, c.pool_seconds, c.approvals_required, c.updated_at
  from public.group_members m
  join public.groups g on g.id=m.group_id
  join public.group_config c on c.group_id=g.id
  where m.user_id = auth.uid() and m.left_at is null
  order by g.id;
end; $$;

create or replace function public.get_group(p_group_id uuid)
returns jsonb language sql security definer stable set search_path = public, pg_temp as $$
  select case when public.is_group_member(p_group_id) then jsonb_build_object(
    'group', (select to_jsonb(g) from public.groups g where g.id=p_group_id),
    'config', (select to_jsonb(c) from public.group_config c where c.group_id=p_group_id),
    'members', (select coalesce(jsonb_agg(jsonb_build_object(
        'user_id', m.user_id, 'display_name', p.display_name,
        'avatar_color_hex', p.avatar_color_hex, 'role', m.role,
        'joined_at', m.joined_at, 'configured_at', m.configured_at)), '[]'::jsonb)
      from public.group_members m join public.profiles p on p.id=m.user_id
      where m.group_id=p_group_id and m.left_at is null)
  ) end;
$$;

create or replace function public.set_member_configured(p_group_id uuid, p_configured boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.group_members set configured_at = case when p_configured then now() else null end
    where group_id=p_group_id and user_id=auth.uid();
end; $$;

create or replace function public.leave_group(p_group_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if exists (select 1 from public.groups where id=p_group_id and owner_id=auth.uid())
    then raise exception 'owner cannot leave; delete the group instead'; end if;
  update public.group_members set left_at = now()
    where group_id=p_group_id and user_id=auth.uid();
end; $$;

create or replace function public.remove_group_member(p_group_id uuid, p_user_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not exists (select 1 from public.groups where id=p_group_id and owner_id=auth.uid())
    then raise exception 'owner only'; end if;
  if p_user_id = auth.uid() then raise exception 'use delete_group'; end if;
  update public.group_members set left_at = now(), removed_by = auth.uid()
    where group_id=p_group_id and user_id=p_user_id;
end; $$;

create or replace function public.reinstate_group_member(p_group_id uuid, p_user_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not exists (select 1 from public.groups where id=p_group_id and owner_id=auth.uid())
    then raise exception 'only the owner can reinstate members'; end if;
  -- Only reinstate an owner-REMOVED member (removed_by is not null). A member who
  -- chose to leave (left_at set, removed_by null) must redeem an invite again
  -- rather than be force-rejoined without their consent. Clear left_at too, else
  -- every active-membership gate (keyed on left_at is null) still excludes them.
  update public.group_members set removed_by = null, left_at = null
    where group_id=p_group_id and user_id=p_user_id and removed_by is not null;
end; $$;

create or replace function public.delete_group(p_group_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not exists (select 1 from public.groups where id=p_group_id and owner_id=auth.uid())
    then raise exception 'owner only'; end if;
  delete from public.groups where id=p_group_id;  -- cascades members/config/invites
end; $$;
