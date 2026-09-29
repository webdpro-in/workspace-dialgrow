-- Workspace capabilities, scoped task creation, employee approvals and group management.
alter table public.roles add column if not exists can_create_roles boolean not null default false;
alter table public.roles add column if not exists can_create_teams boolean not null default false;
alter table public.roles add column if not exists can_create_employees boolean not null default false;
alter table public.roles add column if not exists metadata jsonb not null default '{}'::jsonb;
alter table public.profiles add column if not exists created_by uuid references auth.users(id) on delete set null;
alter table public.profiles add column if not exists employee_creation_limit integer not null default 4;

create table if not exists public.employee_creation_requests (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  requested_by uuid not null references auth.users(id) on delete cascade,
  requester_role_id uuid references public.roles(id) on delete set null,
  current_limit integer not null default 4,
  requested_slots integer not null default 4 check (requested_slots between 1 and 100),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  reviewer_note text not null default '',
  created_at timestamptz not null default now()
);
create unique index if not exists one_pending_employee_request_per_user on public.employee_creation_requests(requested_by) where status = 'pending';
grant select, insert on public.employee_creation_requests to authenticated;
alter table public.employee_creation_requests enable row level security;

update public.roles
set can_create_roles = true, can_create_teams = true, can_create_employees = true
where name in ('Main Admin', 'Customer Success', 'Full Stack Developer', 'Operations Lead', 'Team Lead', 'Technical Lead');

create or replace function public.has_role_capability(capability text)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.is_org_admin() or exists (
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid() and ur.is_primary = true
      and ((capability = 'roles' and r.can_create_roles) or (capability = 'teams' and r.can_create_teams) or (capability = 'employees' and r.can_create_employees)
        or (capability in ('roles', 'teams', 'employees') and r.name in ('Customer Success', 'Full Stack Developer', 'Main Admin', 'Operations Lead', 'Team Lead', 'Technical Lead')))
  )
$$;

create or replace function public.can_create_common_note()
returns boolean language sql stable security definer set search_path = public
as $$
  select public.is_org_admin() or exists (
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid() and ur.is_primary = true
      and r.name in ('Customer Success', 'Full Stack Developer', 'Main Admin', 'Operations Lead', 'Team Lead', 'Technical Lead')
  )
$$;

create or replace function public.can_manage_channel(channel_uuid uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select public.is_org_admin() or exists (select 1 from public.channels c where c.id = channel_uuid and c.created_by = auth.uid()) $$;

drop policy if exists "team leads create roles" on public.roles;
create policy "team leads create roles" on public.roles for insert to authenticated with check (organization_id = public.current_org_id() and public.has_role_capability('roles'));
drop policy if exists "leaders create teams" on public.teams;
drop policy if exists "leaders update teams" on public.teams;
drop policy if exists "leaders delete teams" on public.teams;
create policy "leaders create teams" on public.teams for insert to authenticated with check (organization_id = public.current_org_id() and lead_id = auth.uid() and public.has_role_capability('teams'));
create policy "leaders update teams" on public.teams for update to authenticated using (organization_id = public.current_org_id() and (public.is_org_admin() or lead_id = auth.uid())) with check (organization_id = public.current_org_id() and (public.is_org_admin() or lead_id = auth.uid()));
create policy "leaders delete teams" on public.teams for delete to authenticated using (organization_id = public.current_org_id() and (public.is_org_admin() or lead_id = auth.uid()));
drop policy if exists "admins assign team members" on public.team_members;
create policy "admins assign team members" on public.team_members for insert to authenticated with check ((public.is_org_admin() or exists (select 1 from public.teams own_team where own_team.id = team_id and own_team.lead_id = auth.uid())) and exists (select 1 from public.teams t where t.id = team_id and t.organization_id = public.current_org_id()));
drop policy if exists "same organization tasks in scope" on public.tasks;
drop policy if exists "scoped task creation" on public.tasks;
create policy "same organization tasks in scope" on public.tasks for select to authenticated using (organization_id = public.current_org_id() and (team_id is null or public.is_org_admin() or creator_id = auth.uid() or assignee_id = auth.uid() or reviewer_id = auth.uid() or exists (select 1 from public.team_members tm where tm.team_id = tasks.team_id and tm.user_id = auth.uid()) or exists (select 1 from public.teams t where t.id = tasks.team_id and t.lead_id = auth.uid())));
create policy "scoped task creation" on public.tasks for insert to authenticated with check (organization_id = public.current_org_id() and creator_id = auth.uid() and ((team_id is null and public.can_create_common_note()) or (team_id is not null and (public.is_org_admin() or exists (select 1 from public.team_members tm where tm.team_id = tasks.team_id and tm.user_id = auth.uid()) or exists (select 1 from public.teams t where t.id = tasks.team_id and t.lead_id = auth.uid())))));
drop policy if exists "leaders create channels" on public.channels;
create policy "leaders create channels" on public.channels for insert to authenticated with check (organization_id = public.current_org_id() and created_by = auth.uid() and public.has_role_capability('teams'));

drop policy if exists "requester or admin sees employee requests" on public.employee_creation_requests;
drop policy if exists "eligible users request employee slots" on public.employee_creation_requests;
create policy "requester or admin sees employee requests" on public.employee_creation_requests for select to authenticated using (organization_id = public.current_org_id() and (requested_by = auth.uid() or public.is_org_admin()));
create policy "eligible users request employee slots" on public.employee_creation_requests for insert to authenticated with check (organization_id = public.current_org_id() and requested_by = auth.uid() and public.has_role_capability('employees'));

create or replace function public.request_employee_creation_slots(requested_slots integer default 4)
returns uuid language plpgsql security definer set search_path = public
as $$
declare request_id uuid; org_id uuid; role_id uuid; current_limit integer;
begin
  if not public.has_role_capability('employees') then raise exception 'Your role cannot create employee accounts'; end if;
  if requested_slots is null or requested_slots < 1 or requested_slots > 100 then raise exception 'Request between 1 and 100 employee slots'; end if;
  org_id := public.current_org_id();
  select ur.role_id into role_id from public.user_roles ur where ur.user_id = auth.uid() and ur.is_primary = true limit 1;
  select employee_creation_limit into current_limit from public.profiles where id = auth.uid();
  insert into public.employee_creation_requests(organization_id, requested_by, requester_role_id, current_limit, requested_slots)
  values (org_id, auth.uid(), role_id, coalesce(current_limit, 4), requested_slots)
  on conflict (requested_by) where status = 'pending' do update set requested_slots = excluded.requested_slots, current_limit = excluded.current_limit
  returning id into request_id;
  return request_id;
end;
$$;
revoke all on function public.request_employee_creation_slots(integer) from public;
grant execute on function public.request_employee_creation_slots(integer) to authenticated;

create or replace function public.review_employee_creation_request(request_uuid uuid, approve_request boolean, review_note text default '')
returns jsonb language plpgsql security definer set search_path = public
as $$
declare request_row public.employee_creation_requests%rowtype; next_limit integer;
begin
  if not public.is_org_admin() then raise exception 'Only the Main Admin can review employee requests'; end if;
  select * into request_row from public.employee_creation_requests where id = request_uuid and organization_id = public.current_org_id() for update;
  if request_row.id is null then raise exception 'Employee creation request not found'; end if;
  if request_row.status <> 'pending' then raise exception 'This request has already been reviewed'; end if;
  if approve_request then
    select greatest(employee_creation_limit, request_row.current_limit) + request_row.requested_slots into next_limit from public.profiles where id = request_row.requested_by;
    update public.profiles set employee_creation_limit = least(coalesce(next_limit, request_row.current_limit + request_row.requested_slots), 10000) where id = request_row.requested_by;
  end if;
  update public.employee_creation_requests set status = case when approve_request then 'approved' else 'rejected' end, reviewed_by = auth.uid(), reviewed_at = now(), reviewer_note = coalesce(review_note, '') where id = request_uuid;
  return jsonb_build_object('ok', true, 'status', case when approve_request then 'approved' else 'rejected' end);
end;
$$;
revoke all on function public.review_employee_creation_request(uuid, boolean, text) from public;
grant execute on function public.review_employee_creation_request(uuid, boolean, text) to authenticated;
