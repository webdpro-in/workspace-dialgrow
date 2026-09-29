-- One attendance row per employee per local workday.
alter table public.attendance add column if not exists work_date date;
update public.attendance
set work_date = (coalesce(check_in_at, check_out_at, created_at) at time zone coalesce(timezone, 'Asia/Kolkata'))::date
where work_date is null;

-- Merge any legacy toggle-created duplicates before adding the unique index.
with ranked as (
  select id,
    row_number() over (partition by user_id, work_date order by coalesce(check_in_at, check_out_at, created_at), created_at, id) as row_number,
    min(check_in_at) over (partition by user_id, work_date) as first_check_in,
    max(check_out_at) over (partition by user_id, work_date) as last_check_out
  from public.attendance
  where work_date is not null
)
update public.attendance a
set check_in_at = ranked.first_check_in,
    check_out_at = ranked.last_check_out,
    status = case
      when ranked.first_check_in is null then 'not_checked_in'::public.attendance_status
      when ranked.last_check_out is null then 'working'::public.attendance_status
      else 'checked_out'::public.attendance_status
    end
from ranked
where a.id = ranked.id and ranked.row_number = 1;

with ranked as (
  select id, row_number() over (partition by user_id, work_date order by coalesce(check_in_at, check_out_at, created_at), created_at, id) as row_number
  from public.attendance
  where work_date is not null
)
delete from public.attendance a using ranked
where a.id = ranked.id and ranked.row_number > 1;

alter table public.attendance alter column work_date set default current_date;
alter table public.attendance alter column work_date set not null;
create unique index if not exists attendance_one_row_per_user_per_day on public.attendance(user_id, work_date);

create or replace function public.is_checked_in_today()
returns boolean language sql stable security definer set search_path = public
as $$
  select public.is_org_admin() or exists (
    select 1
    from public.attendance a
    join public.profiles p on p.id = a.user_id
    where a.user_id = auth.uid()
      and a.status = 'working'
      and a.check_in_at is not null
      and a.check_out_at is null
      and a.work_date = (now() at time zone coalesce(a.timezone, p.timezone, 'Asia/Kolkata'))::date
  )
$$;

create or replace function public.record_attendance_event(action text, timezone_name text default 'Asia/Kolkata', event_session_id text default null)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  attendance_row public.attendance%rowtype;
  local_day date;
  normalized_timezone text := coalesce(nullif(trim(timezone_name), ''), 'Asia/Kolkata');
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then raise exception 'Not authenticated'; end if;
  if action not in ('check_in', 'check_out') then raise exception 'Attendance action must be check_in or check_out'; end if;
  begin
    local_day := (now() at time zone normalized_timezone)::date;
  exception when invalid_parameter_value then
    raise exception 'Invalid timezone';
  end;
  select * into attendance_row from public.attendance where user_id = current_user_id and work_date = local_day for update;
  if action = 'check_in' then
    if attendance_row.id is not null and attendance_row.check_in_at is not null then
      if attendance_row.check_out_at is not null then raise exception 'You have already checked in and checked out today'; end if;
      raise exception 'You have already checked in today';
    end if;
    if attendance_row.id is null then
      insert into public.attendance(organization_id, user_id, status, check_in_at, timezone, session_id, work_date)
      values (public.current_org_id(), current_user_id, 'working', now(), normalized_timezone, event_session_id, local_day)
      returning * into attendance_row;
    else
      update public.attendance set status = 'working', check_in_at = now(), check_out_at = null, timezone = normalized_timezone, session_id = event_session_id where id = attendance_row.id returning * into attendance_row;
    end if;
  else
    if attendance_row.id is null or attendance_row.check_in_at is null then raise exception 'Check in before checking out'; end if;
    if attendance_row.check_out_at is not null then raise exception 'You have already checked out today'; end if;
    update public.attendance set status = 'checked_out', check_out_at = now() where id = attendance_row.id returning * into attendance_row;
  end if;
  return to_jsonb(attendance_row);
end;
$$;
revoke all on function public.record_attendance_event(text, text, text) from public;
grant execute on function public.record_attendance_event(text, text, text) to authenticated;

create or replace function public.admin_update_employee_password(target_user_id uuid, new_password text)
returns boolean language plpgsql security definer set search_path = public, auth, extensions
as $$
begin
  if not public.is_org_admin() then raise exception 'Only the Main Admin can change employee passwords'; end if;
  if target_user_id = auth.uid() then raise exception 'Use your account security settings to change your own password'; end if;
  if new_password is null or length(new_password) < 10 then raise exception 'Password must be at least 10 characters'; end if;
  if not exists (select 1 from public.profiles where id = target_user_id and organization_id = public.current_org_id()) then raise exception 'Employee is not in your workspace'; end if;
  update auth.users set encrypted_password = extensions.crypt(new_password, extensions.gen_salt('bf')), updated_at = now() where id = target_user_id and deleted_at is null;
  if not found then raise exception 'Employee login was not found'; end if;
  insert into public.audit_logs(organization_id, actor_id, action, object_type, object_id, metadata)
  values (public.current_org_id(), auth.uid(), 'employee_password_updated', 'profile', target_user_id, jsonb_build_object('admin_only', true));
  return true;
end;
$$;
revoke all on function public.admin_update_employee_password(uuid, text) from public;
grant execute on function public.admin_update_employee_password(uuid, text) to authenticated;

drop policy if exists "same organization tasks in scope" on public.tasks;
drop policy if exists "scoped task creation" on public.tasks;
drop policy if exists "scoped task updates" on public.tasks;
drop policy if exists "scoped task deletes" on public.tasks;
create policy "same organization tasks in scope" on public.tasks for select to authenticated using (organization_id = public.current_org_id() and public.is_checked_in_today() and (team_id is null or public.is_org_admin() or creator_id = auth.uid() or assignee_id = auth.uid() or reviewer_id = auth.uid() or exists (select 1 from public.team_members tm where tm.team_id = tasks.team_id and tm.user_id = auth.uid()) or exists (select 1 from public.teams t where t.id = tasks.team_id and t.lead_id = auth.uid())));
create policy "scoped task creation" on public.tasks for insert to authenticated with check (organization_id = public.current_org_id() and public.is_checked_in_today() and creator_id = auth.uid() and ((team_id is null and public.can_create_common_note()) or (team_id is not null and (public.is_org_admin() or exists (select 1 from public.team_members tm where tm.team_id = tasks.team_id and tm.user_id = auth.uid()) or exists (select 1 from public.teams t where t.id = tasks.team_id and t.lead_id = auth.uid())))));
create policy "scoped task updates" on public.tasks for update to authenticated using (organization_id = public.current_org_id() and public.is_checked_in_today() and (public.is_org_admin() or creator_id = auth.uid() or assignee_id = auth.uid() or reviewer_id = auth.uid())) with check (organization_id = public.current_org_id() and public.is_checked_in_today());
create policy "scoped task deletes" on public.tasks for delete to authenticated using (organization_id = public.current_org_id() and public.is_checked_in_today() and (public.is_org_admin() or creator_id = auth.uid() or exists (select 1 from public.teams t where t.id = tasks.team_id and t.lead_id = auth.uid())));
