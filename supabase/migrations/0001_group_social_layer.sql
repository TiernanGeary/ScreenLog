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
returns boolean language sql security definer stable as $$
  select exists (
    select 1 from public.group_members m
    where m.group_id = p_group_id and m.user_id = auth.uid() and m.left_at is null
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
create or replace function public.gen_group_code() returns text language sql as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
    (floor(random()*32)+1)::int, 1), '') from generate_series(1,8);
$$;

create or replace function public.create_group(
  p_name text, p_mode text, p_app_names text[],
  p_limit_seconds int, p_approvals_required int, p_owner_time_zone text)
returns table(group_id uuid, code text)
language plpgsql security definer as $$
declare g_id uuid; inv_code text;
begin
  if auth.uid() is null then raise exception 'auth required'; end if;
  insert into public.groups(owner_id, name, mode, owner_time_zone)
    values (auth.uid(), p_name, p_mode, coalesce(p_owner_time_zone,'UTC'))
    returning id into g_id;
  insert into public.group_members(group_id, user_id, role) values (g_id, auth.uid(), 'owner');
  insert into public.group_config(group_id, app_names,
      per_member_limit_seconds, pool_seconds, approvals_required)
    values (g_id, coalesce(p_app_names,'{}'),
      case when p_mode='per_member' then p_limit_seconds end,
      case when p_mode='pool' then p_limit_seconds end,
      greatest(coalesce(p_approvals_required,1),1));
  inv_code := public.gen_group_code();
  insert into public.group_invites(code, group_id, created_by, expires_at)
    values (inv_code, g_id, auth.uid(), now() + interval '30 days');
  return query select g_id, inv_code;
end; $$;

create or replace function public.create_group_invite(p_group_id uuid)
returns table(code text, expires_at timestamptz)
language plpgsql security definer as $$
declare inv_code text; exp timestamptz;
begin
  if not exists (select 1 from public.groups where id=p_group_id and owner_id=auth.uid())
    then raise exception 'owner only'; end if;
  inv_code := public.gen_group_code(); exp := now() + interval '30 days';
  insert into public.group_invites(code, group_id, created_by, expires_at)
    values (inv_code, p_group_id, auth.uid(), exp);
  return query select inv_code, exp;
end; $$;

create or replace function public.peek_group_invite(p_code text)
returns table(group_id uuid, group_name text, owner_display_name text, mode text)
language plpgsql security definer as $$
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
language plpgsql security definer as $$
declare g_id uuid; g_name text;
begin
  if auth.uid() is null then raise exception 'auth required'; end if;
  select i.group_id, g.name into g_id, g_name
    from public.group_invites i join public.groups g on g.id=i.group_id
    where i.code = upper(p_code) and i.expires_at > now();
  if g_id is null then raise exception 'invalid or expired code'; end if;
  insert into public.group_members(group_id, user_id, role)
    values (g_id, auth.uid(), 'member')
    on conflict (group_id, user_id) do update set left_at = null;  -- idempotent / rejoin
  return query select g_id, g_name;
end; $$;

create or replace function public.get_my_groups()
returns table(id uuid, name text, mode text, owner_id uuid, owner_time_zone text,
  role text, configured_at timestamptz, member_count int,
  app_names text[], per_member_limit_seconds int, pool_seconds int,
  approvals_required int, updated_at timestamptz)
language sql security definer stable as $$
  select g.id, g.name, g.mode, g.owner_id, g.owner_time_zone,
    m.role, m.configured_at,
    (select count(*) from public.group_members mm where mm.group_id=g.id and mm.left_at is null)::int,
    c.app_names, c.per_member_limit_seconds, c.pool_seconds, c.approvals_required, c.updated_at
  from public.group_members m
  join public.groups g on g.id=m.group_id
  join public.group_config c on c.group_id=g.id
  where m.user_id = auth.uid() and m.left_at is null;
$$;

create or replace function public.get_group(p_group_id uuid)
returns jsonb language sql security definer stable as $$
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
returns void language plpgsql security definer as $$
begin
  update public.group_members set configured_at = case when p_configured then now() else null end
    where group_id=p_group_id and user_id=auth.uid();
end; $$;

create or replace function public.leave_group(p_group_id uuid)
returns void language plpgsql security definer as $$
begin
  if exists (select 1 from public.groups where id=p_group_id and owner_id=auth.uid())
    then raise exception 'owner cannot leave; delete the group instead'; end if;
  update public.group_members set left_at = now()
    where group_id=p_group_id and user_id=auth.uid();
end; $$;

create or replace function public.remove_group_member(p_group_id uuid, p_user_id uuid)
returns void language plpgsql security definer as $$
begin
  if not exists (select 1 from public.groups where id=p_group_id and owner_id=auth.uid())
    then raise exception 'owner only'; end if;
  if p_user_id = auth.uid() then raise exception 'use delete_group'; end if;
  update public.group_members set left_at = now() where group_id=p_group_id and user_id=p_user_id;
end; $$;

create or replace function public.delete_group(p_group_id uuid)
returns void language plpgsql security definer as $$
begin
  if not exists (select 1 from public.groups where id=p_group_id and owner_id=auth.uid())
    then raise exception 'owner only'; end if;
  delete from public.groups where id=p_group_id;  -- cascades members/config/invites
end; $$;
