-- SP3: shared pool usage. Apply in the Supabase SQL editor (after 0001/0002).
create table if not exists public.group_usage (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  day text not null,                         -- owner-TZ day key 'YYYY-MM-DD'
  selected_app_seconds int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (group_id, user_id, day)
);
alter table public.group_usage enable row level security;
create policy group_usage_select on public.group_usage for select
  using (public.is_group_member(group_id));

-- Owner-TZ day key for a group.
create or replace function public.group_owner_day(p_group_id uuid)
returns text language plpgsql security definer stable set search_path = public, pg_temp as $$
declare owner_tz text;
begin
  select coalesce(owner_time_zone, 'UTC') into owner_tz
    from public.groups where id = p_group_id;
  owner_tz := coalesce(owner_tz, 'UTC');
  begin
    return to_char((now() at time zone owner_tz), 'YYYY-MM-DD');
  exception when others then
    return to_char((now() at time zone 'UTC'), 'YYYY-MM-DD');
  end;
end;
$$;

-- Report a member's cumulative selected-app seconds for today; return pool state.
create or replace function public.report_group_usage(p_group_id uuid, p_selected_app_seconds int)
returns table(pool_seconds int, used_seconds int, remaining_seconds int, exhausted boolean)
language plpgsql security definer set search_path = public, pg_temp as $$
declare d text; pool int; used int;
begin
  if not public.is_group_member(p_group_id) then raise exception 'not a member'; end if;
  d := public.group_owner_day(p_group_id);
  insert into public.group_usage(group_id, user_id, day, selected_app_seconds, updated_at)
    values (p_group_id, auth.uid(), d, greatest(coalesce(p_selected_app_seconds,0),0), now())
    on conflict (group_id, user_id, day) do update
      set selected_app_seconds = greatest(excluded.selected_app_seconds, public.group_usage.selected_app_seconds),
          updated_at = now();
  select pool_seconds into pool from public.group_config where group_id = p_group_id;
  select coalesce(sum(u.selected_app_seconds),0) into used
    from public.group_usage u
    join public.group_members m
      on m.group_id = u.group_id and m.user_id = u.user_id
    where u.group_id = p_group_id and u.day = d
      and m.left_at is null and m.removed_by is null;
  return query select coalesce(pool,0), used, greatest(coalesce(pool,0)-used,0),
                      (used >= coalesce(pool,0) and coalesce(pool,0) > 0);
end; $$;

create or replace function public.get_group_pool_state(p_group_id uuid)
returns table(pool_seconds int, used_seconds int, remaining_seconds int, exhausted boolean)
language plpgsql security definer stable set search_path = public, pg_temp as $$
declare d text; pool int; used int;
begin
  if not public.is_group_member(p_group_id) then raise exception 'not a member'; end if;
  d := public.group_owner_day(p_group_id);
  select pool_seconds into pool from public.group_config where group_id = p_group_id;
  select coalesce(sum(u.selected_app_seconds),0) into used
    from public.group_usage u
    join public.group_members m
      on m.group_id = u.group_id and m.user_id = u.user_id
    where u.group_id = p_group_id and u.day = d
      and m.left_at is null and m.removed_by is null;
  return query select coalesce(pool,0), used, greatest(coalesce(pool,0)-used,0),
                      (used >= coalesce(pool,0) and coalesce(pool,0) > 0);
end; $$;
