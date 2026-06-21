-- SP4: group-scoped time requests. Apply in the Supabase SQL editor.
-- Assumes 0001_group_social_layer.sql is already applied and the existing
-- time_requests table (id, group_id text, requester_id, recipient_ids uuid[],
-- requested_seconds, message, photo_path, status, approved_by, created_at,
-- expires_at, resolved_at, approved_expires_at, collected_at, group_app_names).

alter table public.time_requests
  add column if not exists social_group_id uuid references public.groups(id) on delete cascade,
  add column if not exists approvals_required int,
  add column if not exists approvers uuid[] not null default '{}';

-- Send a group time request: recipients = all other active members; approvals
-- required = the group's configured count. p_block_group_id is the requester's
-- LOCAL block group id ("group.<social_group_id>") used later for the unblock.
create or replace function public.send_group_time_request(
  p_request_id uuid, p_social_group_id uuid, p_block_group_id text, p_seconds int, p_message text, p_photo_path text)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
  declare reqd int; recips uuid[]; names text[]; reqname text;
begin
  if not public.is_group_member(p_social_group_id) then raise exception 'not a member'; end if;
  if lower(p_block_group_id) is distinct from 'group.' || p_social_group_id::text then raise exception 'block group id mismatch'; end if;
  -- Time requests extend a per-member daily limit. Pool groups reset daily and their
  -- exhaustion override deliberately takes precedence over unblock sessions, so a
  -- collected request would be silently swallowed — refuse them at the source (the
  -- UI already only offers "Ask the group" in per-member mode).
  if (select mode from public.groups where id = p_social_group_id) <> 'per_member' then
    raise exception 'time requests are only for per-member groups';
  end if;
  select approvals_required into reqd from public.group_config where group_id = p_social_group_id;
  select array_agg(user_id) into recips from public.group_members
    where group_id = p_social_group_id and left_at is null and user_id <> auth.uid();
  if coalesce(array_length(recips,1),0) = 0 then raise exception 'no recipients to approve'; end if;
  select app_names into names from public.group_config where group_id = p_social_group_id;
  select display_name into reqname from public.profiles where id = auth.uid();
  insert into public.time_requests(
    id, group_id, social_group_id, requester_id, requester_display_name, recipient_ids, requested_seconds,
    message, photo_path, status, approvals_required, approvers, group_app_names,
    created_at, expires_at)
  values (
    p_request_id, p_block_group_id, p_social_group_id, auth.uid(), reqname, coalesce(recips,'{}'),
    p_seconds, p_message, p_photo_path, 'pending',
    greatest(1, least(coalesce(reqd,1), array_length(recips,1))), '{}',
    names, now(), now() + interval '8 hours');
  return p_request_id;
end; $$;

-- Approve/deny a group time request. Approval is counted; once approvals_required
-- distinct members approve, status flips to 'approved'.
-- Returns (status, transitioned): transitioned is true only when THIS call flipped
-- the request pending->approved, so exactly one approver pushes the requester.
-- (drop first: the return type changed from a scalar text.)
drop function if exists public.respond_group_time_request(uuid, boolean);
create function public.respond_group_time_request(p_request_id uuid, p_approve boolean)
returns table(status text, transitioned boolean)
language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.time_requests%rowtype; new_status text; eff int;
begin
  select * into r from public.time_requests where id = p_request_id for update;
  if r.id is null then raise exception 'no such request'; end if;
  -- Group RPC: refuse friend rows so a friend request can only be resolved by
  -- respond_to_time_request (and never picks up group approval semantics).
  if r.social_group_id is null then raise exception 'not a group request'; end if;
  if not (auth.uid() = any(r.recipient_ids)) then raise exception 'not a recipient'; end if;
  if not public.is_group_member(r.social_group_id) then raise exception 'not a member'; end if;
  if r.status <> 'pending' then return query select r.status, false; return; end if;
  if r.expires_at is not null and r.expires_at <= now() then
    update public.time_requests set status='expired', resolved_at=now() where id=p_request_id and status='pending';
    return query select 'expired'::text, false; return;
  end if;
  if not p_approve then
    update public.time_requests set status='denied', resolved_at=now() where id=p_request_id;
    return query select 'denied'::text, false; return;
  end if;
  if not (auth.uid() = any(r.approvers)) then
    r.approvers := array_append(r.approvers, auth.uid());
  end if;
  -- Count the distinct members who have approved (r.approvers is maintained
  -- dedup'd above) and compare against the quorum frozen at send time. An
  -- approval is a point-in-time consent: it keeps counting even if that member
  -- later leaves, so a legitimately-met quorum is never silently dropped. And
  -- because removing a pending NON-approver changes neither the array nor the
  -- frozen bar, an owner still cannot lower the quorum by pruning recipients.
  eff := coalesce(array_length(r.approvers, 1), 0);
  new_status := case when eff >= greatest(1, coalesce(r.approvals_required, 1))
                     then 'approved' else 'pending' end;
  update public.time_requests
    set approvers = r.approvers,
        status = new_status,
        resolved_at = case when new_status='approved' then now() else resolved_at end,
        approved_expires_at = case when new_status='approved' then now() + interval '24 hours' else approved_expires_at end
    where id = p_request_id;
  -- We only reach here from status='pending', so a now-'approved' result means
  -- THIS call caused the transition.
  return query select new_status, (new_status = 'approved'); return;
end; $$;

create or replace function public.collect_group_time_request(p_request_id uuid)
returns text language plpgsql security definer set search_path = public, pg_temp as $$
begin
  -- Group-only and gated on membership (parity with send/respond): refuse friend
  -- rows, and stop a member who left or was removed from collecting their request.
  update public.time_requests set status='collected', collected_at=now()
    where id = p_request_id and requester_id = auth.uid() and status = 'approved'
      and (approved_expires_at is null or approved_expires_at > now())
      and social_group_id is not null and public.is_group_member(social_group_id);
  return 'collected';
end; $$;
