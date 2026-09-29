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
