-- DialGrow Workspace core schema.
-- Run this in the Supabase SQL editor after enabling Auth.

create extension if not exists "uuid-ossp";

create type public.role_status as enum ('draft', 'active', 'archived');
create type public.task_status as enum ('backlog', 'assigned', 'accepted', 'in_progress', 'blocked', 'submitted', 'under_review', 'changes_requested', 'approved', 'completed', 'archived');
create type public.task_priority as enum ('low', 'medium', 'high', 'urgent');
create type public.attendance_status as enum ('not_checked_in', 'working', 'on_break', 'checked_out', 'absent', 'leave', 'half_day');

create table if not exists public.organizations (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  slug text unique not null,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.departments (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.roles (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  description text not null default '',
  layer text not null default 'Custom',
  dashboard_template text not null default 'employee',
  responsibilities text[] not null default '{}',
  visibility_scope text not null default 'own',
  can_create_roles boolean not null default false,
  can_create_teams boolean not null default false,
  can_create_employees boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  status public.role_status not null default 'draft',
  created_at timestamptz not null default now(),
  unique(organization_id, name)
);

alter table public.roles add column if not exists can_create_roles boolean not null default false;
alter table public.roles add column if not exists can_create_teams boolean not null default false;
alter table public.roles add column if not exists can_create_employees boolean not null default false;
alter table public.roles add column if not exists metadata jsonb not null default '{}'::jsonb;

create table if not exists public.permissions (
  id uuid primary key default uuid_generate_v4(),
  key text unique not null,
  module text not null,
  action text not null
);

create table if not exists public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  primary key (role_id, permission_id)
);

create table if not exists public.teams (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  department_id uuid references public.departments(id) on delete set null,
  name text not null,
  description text not null default '',
  lead_id uuid references auth.users(id) on delete set null,
  scope jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid references public.organizations(id) on delete set null,
  dg_id text unique,
  full_name text not null,
  email text not null,
  initials text,
  avatar_color text default 'mint',
  job_title text,
  status text default 'active',
  work_start_time time not null default '09:30',
  work_end_time time not null default '18:30',
  work_days smallint[] not null default '{1,2,3,4,5}',
  timezone text not null default 'Asia/Kolkata',
  created_by uuid references auth.users(id) on delete set null,
  employee_creation_limit integer not null default 4 check (employee_creation_limit between 4 and 10000),
  created_at timestamptz not null default now()
);

alter table public.profiles add column if not exists work_start_time time not null default '09:30';
alter table public.profiles add column if not exists work_end_time time not null default '18:30';
alter table public.profiles add column if not exists work_days smallint[] not null default '{1,2,3,4,5}';
alter table public.profiles add column if not exists timezone text not null default 'Asia/Kolkata';
alter table public.profiles add column if not exists dg_id text;
alter table public.profiles add column if not exists created_by uuid references auth.users(id) on delete set null;
alter table public.profiles add column if not exists employee_creation_limit integer not null default 4;
create unique index if not exists profiles_dg_id_key on public.profiles (lower(dg_id)) where dg_id is not null;

create table if not exists public.user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete cascade,
  is_primary boolean not null default false,
  primary key (user_id, role_id)
);

create table if not exists public.team_members (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  membership_scope jsonb not null default '{}'::jsonb,
  primary key (team_id, user_id)
);

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

create table if not exists public.projects (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  description text not null default '',
  owner_id uuid references auth.users(id) on delete set null,
  status text not null default 'active',
  due_date date,
  created_at timestamptz not null default now()
);

create table if not exists public.tasks (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid references public.projects(id) on delete set null,
  team_id uuid references public.teams(id) on delete set null,
  creator_id uuid references auth.users(id) on delete set null,
  assignee_id uuid references auth.users(id) on delete set null,
  reviewer_id uuid references auth.users(id) on delete set null,
  reference text not null,
  title text not null,
  description text not null default '',
  acceptance_criteria text,
  task_type text not null default 'operations',
  priority public.task_priority not null default 'medium',
  status public.task_status not null default 'backlog',
  start_date date,
  due_date date,
  estimate_minutes integer,
  progress smallint not null default 0 check (progress between 0 and 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.tasks add column if not exists note_color text not null default 'sun';
alter table public.tasks add column if not exists note_rotation numeric(4,2) not null default 0;
alter table public.tasks add column if not exists repeat_rule text not null default 'once';

create table if not exists public.task_comments (
  id uuid primary key default uuid_generate_v4(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  author_id uuid references auth.users(id) on delete set null,
  body text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.task_activity (
  id uuid primary key default uuid_generate_v4(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.attendance (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status public.attendance_status not null default 'not_checked_in',
  check_in_at timestamptz,
  check_out_at timestamptz,
  timezone text,
  session_id text,
  created_at timestamptz not null default now()
);

create table if not exists public.channels (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  description text default '',
  channel_type text not null default 'team',
  access_scope text not null default 'organization' check (access_scope in ('organization', 'team', 'private')),
  team_id uuid references public.teams(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.channels add column if not exists created_by uuid references auth.users(id) on delete set null;
alter table public.channels add column if not exists access_scope text not null default 'organization';
alter table public.channels add column if not exists team_id uuid references public.teams(id) on delete set null;
create unique index if not exists channels_org_name_key on public.channels (organization_id, lower(name));

create table if not exists public.channel_members (
  channel_id uuid not null references public.channels(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  added_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (channel_id, user_id)
);

create table if not exists public.messages (
  id uuid primary key default uuid_generate_v4(),
  channel_id uuid not null references public.channels(id) on delete cascade,
  author_id uuid references auth.users(id) on delete set null,
  body text not null,
  parent_id uuid references public.messages(id) on delete set null,
  task_id uuid references public.tasks(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.documents (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  owner_id uuid references auth.users(id) on delete set null,
  title text not null,
  description text default '',
  storage_path text,
  document_type text not null default 'file',
  tags text[] not null default '{}',
  visibility_scope jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.documents add column if not exists expires_at timestamptz;
alter table public.documents add column if not exists channel_id uuid references public.channels(id) on delete cascade;

create table if not exists public.team_updates (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  cadence text not null default 'daily' check (cadence in ('daily', 'weekly')),
  work_date date not null default current_date,
  title text not null,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, author_id, cadence, work_date)
);

create table if not exists public.training_courses (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  title text not null,
  description text not null default '',
  required boolean not null default false,
  duration_minutes integer,
  created_at timestamptz not null default now()
);

create table if not exists public.training_assignments (
  id uuid primary key default uuid_generate_v4(),
  course_id uuid not null references public.training_courses(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  role_id uuid references public.roles(id) on delete cascade,
  team_id uuid references public.teams(id) on delete cascade,
  assigned_by uuid references auth.users(id) on delete set null,
  due_date date,
  created_at timestamptz not null default now()
);

create table if not exists public.training_progress (
  assignment_id uuid primary key references public.training_assignments(id) on delete cascade,
  progress smallint not null default 0 check (progress between 0 and 100),
  completed_at timestamptz,
  assessment_score smallint,
  updated_at timestamptz not null default now()
);

create table if not exists public.positions (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  title text not null,
  employment_type text not null,
  work_mode text not null,
  status text not null default 'draft',
  responsibilities text[] not null default '{}',
  skills text[] not null default '{}',
  hiring_owner uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid references public.organizations(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  object_type text not null,
  object_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.announcements (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  author_name text not null default 'Priya Sharma',
  title text not null,
  body text not null,
  audience_scope jsonb not null default '{}'::jsonb,
  scheduled_for timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.social_posts (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null,
  title text not null,
  caption text not null,
  hashtags text[] not null default '{}',
  mentions text[] not null default '{}',
  link text,
  image_path text,
  status text not null default 'draft' check (status in ('draft', 'ready_to_post', 'published', 'failed')),
  audience_scope jsonb not null default '{"type":"all"}'::jsonb,
  engagement jsonb not null default '{"views":0,"likes":0,"comments":0,"reposts":0,"clicks":0}'::jsonb,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists social_posts_org_title_caption_key on public.social_posts (organization_id, lower(title), md5(caption));

create table if not exists public.social_post_recipients (
  post_id uuid not null references public.social_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'ready_to_post' check (status in ('ready_to_post', 'published', 'failed')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

alter table public.organizations enable row level security;
alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.employee_creation_requests enable row level security;
alter table public.projects enable row level security;
alter table public.tasks enable row level security;
alter table public.task_comments enable row level security;
alter table public.attendance enable row level security;
alter table public.channels enable row level security;
alter table public.channel_members enable row level security;
alter table public.messages enable row level security;
alter table public.documents enable row level security;
alter table public.training_courses enable row level security;
alter table public.training_assignments enable row level security;
alter table public.training_progress enable row level security;
alter table public.positions enable row level security;
alter table public.audit_logs enable row level security;
alter table public.user_roles enable row level security;
alter table public.announcements enable row level security;
alter table public.team_updates enable row level security;
alter table public.social_posts enable row level security;
alter table public.social_post_recipients enable row level security;

-- Starter policies: organization isolation is extended by role/scope checks in a follow-up policy migration.
create policy "profiles are visible to authenticated users" on public.profiles for select to authenticated using (true);
create policy "users can update their own profile" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "authenticated users can read workspace roles" on public.roles for select to authenticated using (true);
create policy "authenticated users can read teams" on public.teams for select to authenticated using (true);
create policy "authenticated users can read tasks" on public.tasks for select to authenticated using (true);
create policy "authenticated users can create tasks" on public.tasks for insert to authenticated with check (creator_id = auth.uid());
create policy "authenticated users can update tasks" on public.tasks for update to authenticated using (creator_id = auth.uid() or assignee_id = auth.uid() or reviewer_id = auth.uid());
create policy "authenticated users can read task comments" on public.task_comments for select to authenticated using (true);
create policy "authenticated users can add task comments" on public.task_comments for insert to authenticated with check (author_id = auth.uid());
create policy "authenticated users can read messages" on public.messages for select to authenticated using (true);
create policy "authenticated users can send messages" on public.messages for insert to authenticated with check (author_id = auth.uid());
create policy "authenticated users can read documents" on public.documents for select to authenticated using (true);
create policy "authenticated users can read courses" on public.training_courses for select to authenticated using (true);
create policy "users can read own training assignments" on public.training_assignments for select to authenticated using (user_id = auth.uid());
create policy "users can update own progress" on public.training_progress for all to authenticated using (exists (select 1 from public.training_assignments a where a.id = assignment_id and a.user_id = auth.uid()));
create policy "authenticated users can read positions" on public.positions for select to authenticated using (true);

-- Organization-scoped policies replace the starter policies above once this migration is run.
create or replace function public.current_org_id()
returns uuid language sql stable security definer set search_path = public
as $$ select organization_id from public.profiles where id = auth.uid() $$;

create or replace function public.is_org_admin()
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid() and r.name = 'Main Admin'
  )
$$;

create or replace function public.has_role_capability(capability text)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.is_org_admin() or exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid()
      and ur.is_primary = true
      and (
        (capability = 'roles' and r.can_create_roles)
        or (capability = 'teams' and r.can_create_teams)
        or (capability = 'employees' and r.can_create_employees)
        or (capability in ('roles', 'teams', 'employees') and r.name in ('Customer Success', 'Full Stack Developer', 'Main Admin', 'Operations Lead', 'Team Lead', 'Technical Lead'))
      )
  )
$$;

create or replace function public.can_create_common_note()
returns boolean language sql stable security definer set search_path = public
as $$
  select public.is_org_admin() or exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid()
      and ur.is_primary = true
      and r.name in ('Customer Success', 'Full Stack Developer', 'Main Admin', 'Operations Lead', 'Team Lead', 'Technical Lead')
  )
$$;

create or replace function public.can_manage_channel(channel_uuid uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.is_org_admin() or exists (
    select 1 from public.channels c
    where c.id = channel_uuid and c.created_by = auth.uid()
  )
$$;

create or replace function public.can_access_channel(channel_uuid uuid, viewer_uuid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.channels c
    where c.id = channel_uuid
      and c.organization_id = (select organization_id from public.profiles where id = viewer_uuid)
      and (
        c.access_scope = 'organization'
        or c.created_by = viewer_uuid
        or exists (select 1 from public.channel_members cm where cm.channel_id = c.id and cm.user_id = viewer_uuid)
        or (c.access_scope = 'team' and exists (select 1 from public.team_members tm where tm.team_id = c.team_id and tm.user_id = viewer_uuid))
        or public.is_org_admin()
      )
  )
$$;

create or replace function public.protect_workday_hours()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_org_admin()
    and (new.work_start_time is distinct from old.work_start_time or new.work_end_time is distinct from old.work_end_time) then
    raise exception 'Workday hours are controlled by the Main Admin';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_workday_hours on public.profiles;
create trigger protect_workday_hours before update on public.profiles
for each row execute function public.protect_workday_hours();

drop policy if exists "profiles are visible to authenticated users" on public.profiles;
drop policy if exists "authenticated users can read workspace roles" on public.roles;
drop policy if exists "authenticated users can read teams" on public.teams;
drop policy if exists "authenticated users can read tasks" on public.tasks;
drop policy if exists "authenticated users can create tasks" on public.tasks;
drop policy if exists "authenticated users can update tasks" on public.tasks;
drop policy if exists "authenticated users can read task comments" on public.task_comments;
drop policy if exists "authenticated users can add task comments" on public.task_comments;
drop policy if exists "authenticated users can read messages" on public.messages;
drop policy if exists "authenticated users can send messages" on public.messages;
drop policy if exists "authenticated users can read documents" on public.documents;
drop policy if exists "authenticated users can read courses" on public.training_courses;
drop policy if exists "users can read own training assignments" on public.training_assignments;
drop policy if exists "users can update own progress" on public.training_progress;
drop policy if exists "authenticated users can read positions" on public.positions;

create policy "same organization profiles" on public.profiles for select to authenticated using (organization_id = public.current_org_id());
create policy "admins update workspace profiles" on public.profiles for update to authenticated using (organization_id = public.current_org_id() and public.is_org_admin()) with check (organization_id = public.current_org_id() and public.is_org_admin());
create policy "same organization roles" on public.roles for select to authenticated using (organization_id = public.current_org_id());
create policy "admin creates roles" on public.roles for insert to authenticated with check (organization_id = public.current_org_id() and public.is_org_admin());
create policy "team leads create roles" on public.roles for insert to authenticated with check (organization_id = public.current_org_id() and public.has_role_capability('roles'));
create policy "admin updates roles" on public.roles for update to authenticated using (organization_id = public.current_org_id() and public.is_org_admin()) with check (organization_id = public.current_org_id() and public.is_org_admin());
create policy "own or admin role memberships" on public.user_roles for select to authenticated using (user_id = auth.uid() or public.is_org_admin());
create policy "admin assigns roles" on public.user_roles for insert to authenticated with check (public.is_org_admin());
create policy "admin updates role assignments" on public.user_roles for update to authenticated using (public.is_org_admin()) with check (public.is_org_admin());
create policy "same organization teams" on public.teams for select to authenticated using (organization_id = public.current_org_id());
create policy "leaders create teams" on public.teams for insert to authenticated with check (organization_id = public.current_org_id() and lead_id = auth.uid() and public.has_role_capability('teams'));
create policy "leaders update teams" on public.teams for update to authenticated using (organization_id = public.current_org_id() and (public.is_org_admin() or lead_id = auth.uid())) with check (organization_id = public.current_org_id() and (public.is_org_admin() or lead_id = auth.uid()));
create policy "leaders delete teams" on public.teams for delete to authenticated using (organization_id = public.current_org_id() and (public.is_org_admin() or lead_id = auth.uid()));
create policy "team members visible in scope" on public.team_members for select to authenticated using (
  user_id = auth.uid() or exists (
    select 1 from public.teams t
    where t.id = team_id and t.organization_id = public.current_org_id()
      and (t.lead_id = auth.uid() or public.is_org_admin())
  )
);
create policy "visible channel members" on public.channel_members for select to authenticated using (user_id = auth.uid() or public.is_org_admin() or exists (select 1 from public.channels c where c.id = channel_id and c.created_by = auth.uid()));
create policy "owners add channel members" on public.channel_members for insert to authenticated with check (added_by = auth.uid() and (public.is_org_admin() or exists (select 1 from public.channels c where c.id = channel_id and c.organization_id = public.current_org_id() and c.created_by = auth.uid())));
create policy "owners remove channel members" on public.channel_members for delete to authenticated using (public.is_org_admin() or exists (select 1 from public.channels c where c.id = channel_id and c.created_by = auth.uid()));
create policy "admins assign team members" on public.team_members for insert to authenticated with check (
  (public.is_org_admin() or exists (select 1 from public.teams own_team where own_team.id = team_id and own_team.lead_id = auth.uid())) and exists (
    select 1 from public.teams t
    where t.id = team_id and t.organization_id = public.current_org_id()
  )
);
create policy "own or admin attendance" on public.attendance for select to authenticated using (organization_id = public.current_org_id() and (user_id = auth.uid() or public.is_org_admin()));
create policy "own attendance insert" on public.attendance for insert to authenticated with check (organization_id = public.current_org_id() and user_id = auth.uid());
create policy "own attendance update" on public.attendance for update to authenticated using (organization_id = public.current_org_id() and (user_id = auth.uid() or public.is_org_admin()));
create policy "same organization tasks in scope" on public.tasks for select to authenticated using (organization_id = public.current_org_id() and (team_id is null or public.is_org_admin() or creator_id = auth.uid() or assignee_id = auth.uid() or reviewer_id = auth.uid() or exists (select 1 from public.team_members tm where tm.team_id = tasks.team_id and tm.user_id = auth.uid()) or exists (select 1 from public.teams t where t.id = tasks.team_id and t.lead_id = auth.uid())));
create policy "scoped task creation" on public.tasks for insert to authenticated with check (organization_id = public.current_org_id() and creator_id = auth.uid() and ((team_id is null and public.can_create_common_note()) or (team_id is not null and (public.is_org_admin() or exists (select 1 from public.team_members tm where tm.team_id = tasks.team_id and tm.user_id = auth.uid()) or exists (select 1 from public.teams t where t.id = tasks.team_id and t.lead_id = auth.uid())))));
create policy "scoped task updates" on public.tasks for update to authenticated using (organization_id = public.current_org_id() and (public.is_org_admin() or creator_id = auth.uid() or assignee_id = auth.uid() or reviewer_id = auth.uid()));
create policy "scoped task deletes" on public.tasks for delete to authenticated using (organization_id = public.current_org_id() and (public.is_org_admin() or creator_id = auth.uid() or exists (select 1 from public.teams t where t.id = tasks.team_id and t.lead_id = auth.uid())));
create policy "same organization task comments" on public.task_comments for select to authenticated using (exists (select 1 from public.tasks t where t.id = task_id and t.organization_id = public.current_org_id()));
create policy "scoped task comments" on public.task_comments for insert to authenticated with check (author_id = auth.uid() and exists (select 1 from public.tasks t where t.id = task_id and t.organization_id = public.current_org_id()));
drop policy if exists "same organization channels" on public.channels;
drop policy if exists "visible channels" on public.channels;
create policy "visible channels" on public.channels for select to authenticated using (
  organization_id = public.current_org_id()
  and (access_scope = 'organization' or created_by = auth.uid() or public.can_access_channel(id, auth.uid()))
);
create policy "admin creates channels" on public.channels for insert to authenticated with check (organization_id = public.current_org_id() and public.is_org_admin());
create policy "leaders create channels" on public.channels for insert to authenticated with check (organization_id = public.current_org_id() and created_by = auth.uid() and public.has_role_capability('teams'));
create policy "owners update channels" on public.channels for update to authenticated using (organization_id = public.current_org_id() and (public.is_org_admin() or created_by = auth.uid())) with check (organization_id = public.current_org_id() and (public.is_org_admin() or created_by = auth.uid()));
create policy "owners delete channels" on public.channels for delete to authenticated using (organization_id = public.current_org_id() and (public.is_org_admin() or created_by = auth.uid()));
drop policy if exists "same organization messages" on public.messages;
create policy "visible messages" on public.messages for select to authenticated using (public.can_access_channel(channel_id, auth.uid()));
create policy "scoped message creation" on public.messages for insert to authenticated with check (author_id = auth.uid() and public.can_access_channel(channel_id, auth.uid()));
drop policy if exists "same organization documents" on public.documents;
drop policy if exists "same organization document uploads" on public.documents;
drop policy if exists "scoped message creation" on public.messages;
create policy "same organization documents" on public.documents for select to authenticated using (organization_id = public.current_org_id() and (channel_id is null or public.can_access_channel(channel_id, auth.uid())));
create policy "same organization document uploads" on public.documents for insert to authenticated with check (organization_id = public.current_org_id() and owner_id = auth.uid() and (channel_id is null or public.can_access_channel(channel_id, auth.uid())));
create policy "owners delete documents" on public.documents for delete to authenticated using (organization_id = public.current_org_id() and (public.is_org_admin() or owner_id = auth.uid()));
create policy "same organization team updates" on public.team_updates for select to authenticated using (organization_id = public.current_org_id());
create policy "members create team updates" on public.team_updates for insert to authenticated with check (organization_id = public.current_org_id() and author_id = auth.uid());
create policy "authors update team updates" on public.team_updates for update to authenticated using (organization_id = public.current_org_id() and (public.is_org_admin() or author_id = auth.uid())) with check (organization_id = public.current_org_id() and (public.is_org_admin() or author_id = auth.uid()));
create policy "authors delete team updates" on public.team_updates for delete to authenticated using (organization_id = public.current_org_id() and (public.is_org_admin() or author_id = auth.uid()));
create policy "requester or admin sees employee requests" on public.employee_creation_requests for select to authenticated using (organization_id = public.current_org_id() and (requested_by = auth.uid() or public.is_org_admin()));
create policy "eligible users request employee slots" on public.employee_creation_requests for insert to authenticated with check (organization_id = public.current_org_id() and requested_by = auth.uid() and public.has_role_capability('employees'));

create or replace function public.request_employee_creation_slots(requested_slots integer default 4)
returns uuid language plpgsql security definer set search_path = public
as $$
declare
  request_id uuid;
  org_id uuid;
  role_id uuid;
  current_limit integer;
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
declare
  request_row public.employee_creation_requests%rowtype;
  next_limit integer;
begin
  if not public.is_org_admin() then raise exception 'Only the Main Admin can review employee requests'; end if;
  select * into request_row from public.employee_creation_requests where id = request_uuid and organization_id = public.current_org_id() for update;
  if request_row.id is null then raise exception 'Employee creation request not found'; end if;
  if request_row.status <> 'pending' then raise exception 'This request has already been reviewed'; end if;
  if approve_request then
    select greatest(employee_creation_limit, request_row.current_limit) + request_row.requested_slots into next_limit from public.profiles where id = request_row.requested_by;
    update public.profiles set employee_creation_limit = least(coalesce(next_limit, request_row.current_limit + request_row.requested_slots), 10000) where id = request_row.requested_by;
  end if;
  update public.employee_creation_requests
    set status = case when approve_request then 'approved' else 'rejected' end,
        reviewed_by = auth.uid(), reviewed_at = now(), reviewer_note = coalesce(review_note, '')
    where id = request_uuid;
  return jsonb_build_object('ok', true, 'status', case when approve_request then 'approved' else 'rejected' end);
end;
$$;
revoke all on function public.review_employee_creation_request(uuid, boolean, text) from public;
grant execute on function public.review_employee_creation_request(uuid, boolean, text) to authenticated;
create policy "same organization courses" on public.training_courses for select to authenticated using (organization_id = public.current_org_id());
create policy "own training assignments" on public.training_assignments for select to authenticated using (user_id = auth.uid() or public.is_org_admin());
create policy "own training progress" on public.training_progress for all to authenticated using (exists (select 1 from public.training_assignments a where a.id = assignment_id and (a.user_id = auth.uid() or public.is_org_admin())));
create policy "same organization positions" on public.positions for select to authenticated using (organization_id = public.current_org_id());
create policy "own or admin audit logs" on public.audit_logs for select to authenticated using (actor_id = auth.uid() or public.is_org_admin());
create policy "authenticated login audit" on public.audit_logs for insert to authenticated with check (actor_id = auth.uid() and organization_id = public.current_org_id());
create policy "same organization announcements" on public.announcements for select to authenticated using (organization_id = public.current_org_id());
create schema if not exists private;
revoke all on schema private from public;
create or replace function private.can_view_social_post(post_uuid uuid, viewer_uuid uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.social_post_recipients where post_id = post_uuid and user_id = viewer_uuid) $$;
revoke all on function private.can_view_social_post(uuid, uuid) from public;
grant execute on function private.can_view_social_post(uuid, uuid) to authenticated;

create policy "visible social posts" on public.social_posts for select to authenticated using (
  organization_id = public.current_org_id() and (
    public.is_org_admin() or created_by = auth.uid() or audience_scope ->> 'type' = 'all' or
    private.can_view_social_post(id, auth.uid())
  )
);
create policy "admin creates social posts" on public.social_posts for insert to authenticated with check (organization_id = public.current_org_id() and public.is_org_admin() and created_by = auth.uid());
create policy "admin updates social posts" on public.social_posts for update to authenticated using (organization_id = public.current_org_id() and (public.is_org_admin() or created_by = auth.uid())) with check (organization_id = public.current_org_id());
create policy "admin deletes social posts" on public.social_posts for delete to authenticated using (organization_id = public.current_org_id() and (public.is_org_admin() or created_by = auth.uid()));
create policy "visible post recipients" on public.social_post_recipients for select to authenticated using (user_id = auth.uid() or public.is_org_admin());
create policy "admin assigns post recipients" on public.social_post_recipients for insert to authenticated with check (public.is_org_admin());
create policy "users update own post status" on public.social_post_recipients for update to authenticated using (user_id = auth.uid() or public.is_org_admin()) with check (user_id = auth.uid() or public.is_org_admin());

insert into storage.buckets (id, name, public)
values ('social-posts', 'social-posts', true)
on conflict (id) do update set public = true;

insert into storage.buckets (id, name, public)
values ('team-files', 'team-files', false)
on conflict (id) do update set public = false;

create policy "public can view social posters" on storage.objects for select using (bucket_id = 'social-posts');
create policy "admins upload social posters" on storage.objects for insert to authenticated with check (bucket_id = 'social-posts' and public.is_org_admin());
create policy "admins update social posters" on storage.objects for update to authenticated using (bucket_id = 'social-posts' and public.is_org_admin()) with check (bucket_id = 'social-posts' and public.is_org_admin());
create policy "admins delete social posters" on storage.objects for delete to authenticated using (bucket_id = 'social-posts' and public.is_org_admin());
create policy "members upload team files" on storage.objects for insert to authenticated with check (bucket_id = 'team-files' and name like (public.current_org_id()::text || '/%'));
drop policy if exists "members read team files" on storage.objects;
create policy "members read team files" on storage.objects for select to authenticated using (
  bucket_id = 'team-files'
  and name like (public.current_org_id()::text || '/%')
  and exists (
    select 1 from public.documents d
    where d.storage_path = name
      and (d.channel_id is null or public.can_access_channel(d.channel_id, auth.uid()))
  )
);
create policy "owners delete team files" on storage.objects for delete to authenticated using (bucket_id = 'team-files' and (public.is_org_admin() or name like (public.current_org_id()::text || '/' || auth.uid()::text || '/%')));

-- One-time bootstrap for the owner account. It never accepts a role or organization from the browser.
create or replace function public.bootstrap_dialgrow_workspace()
returns uuid language plpgsql security definer set search_path = public
as $$
declare
  org_id uuid;
  admin_role_id uuid;
begin
  if auth.uid() is null or lower(auth.jwt() ->> 'email') <> 'business@dialgrow.com' then
    raise exception 'Only the DialGrow owner account can bootstrap this workspace';
  end if;
  insert into public.organizations (name, slug) values ('DialGrow', 'dialgrow')
    on conflict (slug) do update set name = excluded.name returning id into org_id;
  insert into public.roles (organization_id, name, layer, description, dashboard_template, visibility_scope, can_create_roles, can_create_teams, can_create_employees, status, responsibilities)
  values
    (org_id, 'Main Admin', 'System', 'Organization-wide control center with full configuration, security and audit access.', 'admin', 'organization', true, true, true, 'active', array['Manage people, roles and teams', 'Configure permissions and policies', 'Review analytics and audit logs']),
    (org_id, 'Team Lead', 'Management', 'Owns a team''s priorities, assignments, reviews and workload.', 'team', 'team', true, true, true, 'active', array['Create and assign team tasks', 'Review outputs and request changes', 'Track team training and workload']),
    (org_id, 'Technical Lead', 'Management', 'Guides technical teams and intern groups with technical task metadata.', 'technical', 'technical', true, true, true, 'active', array['Manage technical work', 'Review projects and coding tasks', 'Support technical training']),
    (org_id, 'Operations Lead', 'Management', 'Runs daily execution, attendance workflows and operational exceptions.', 'operations', 'operations', true, true, true, 'active', array['Monitor check-ins and exceptions', 'Assign operational work', 'Report on completion trends']),
    (org_id, 'Full Stack Developer', 'Technical', 'Executes product work and contributes to technical delivery.', 'technical', 'team', true, true, true, 'active', array['Own technical tasks', 'Attach code and resources', 'Submit work for review']),
    (org_id, 'Customer Success', 'Business', 'Connects customer context to tasks, handoffs and growth outcomes.', 'employee', 'team', true, true, true, 'active', array['Manage customer tasks', 'Share permitted documents', 'Coordinate account follow-ups'])
  on conflict (organization_id, name) do update set description = excluded.description, responsibilities = excluded.responsibilities, can_create_roles = excluded.can_create_roles, can_create_teams = excluded.can_create_teams, can_create_employees = excluded.can_create_employees, status = 'active';
  insert into public.profiles (id, organization_id, dg_id, full_name, email, initials, job_title, timezone)
  values (auth.uid(), org_id, 'dg-0001', coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', 'Durga Prashad'), lower(auth.jwt() ->> 'email'), 'BA', 'Main Admin', 'Asia/Kolkata')
  on conflict (id) do update set organization_id = excluded.organization_id, dg_id = coalesce(public.profiles.dg_id, excluded.dg_id), job_title = 'Main Admin';
  select id into admin_role_id from public.roles where organization_id = org_id and name = 'Main Admin';
  insert into public.user_roles (user_id, role_id, is_primary) values (auth.uid(), admin_role_id, true) on conflict (user_id, role_id) do update set is_primary = true;
  insert into public.channels (organization_id, name, description, channel_type) values (org_id, 'general', 'DialGrow-wide updates and announcements', 'announcement') on conflict do nothing;
  return org_id;
end;
$$;

grant execute on function public.bootstrap_dialgrow_workspace() to authenticated;

-- DG IDs are the employee-facing login identifier; Auth still uses the private email behind it.
create or replace function public.resolve_employee_login(lookup_dg_id text)
returns text language sql stable security definer set search_path = public
as $$ select email from public.profiles where lower(dg_id) = lower(trim(lookup_dg_id)) limit 1 $$;
revoke all on function public.resolve_employee_login(text) from public;
grant execute on function public.resolve_employee_login(text) to anon, authenticated;

create or replace function public.assign_employee_dg_id(target_user_id uuid, new_dg_id text)
returns boolean language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_org_admin() then raise exception 'Only the Main Admin can assign DG IDs'; end if;
  if new_dg_id is null or lower(new_dg_id) !~ '^dg-[0-9]{4}$' or substring(lower(new_dg_id) from 4)::integer not between 1 and 10000 then raise exception 'DG ID must be between dg-0001 and dg-10000'; end if;
  if not exists (select 1 from public.profiles where id = target_user_id and organization_id = public.current_org_id()) then raise exception 'Employee is not in the current organization'; end if;
  update public.profiles set dg_id = lower(trim(new_dg_id)) where id = target_user_id;
  return true;
end;
$$;
revoke all on function public.assign_employee_dg_id(uuid, text) from public;
grant execute on function public.assign_employee_dg_id(uuid, text) to authenticated;

create or replace function public.provision_employee(target_user_id uuid, new_dg_id text, employee_name text, login_email text, role_name text)
returns uuid language plpgsql security definer set search_path = public, auth
as $$
declare
  org_id uuid;
  selected_role_id uuid;
begin
  if not public.is_org_admin() then raise exception 'Only the Main Admin can provision employees'; end if;
  org_id := public.current_org_id();
  if new_dg_id is null or lower(new_dg_id) !~ '^dg-[0-9]{4}$' or substring(lower(new_dg_id) from 4)::integer not between 1 and 10000 then raise exception 'DG ID must be between dg-0001 and dg-10000'; end if;
  if not exists (select 1 from auth.users where id = target_user_id) then raise exception 'Auth account was not created'; end if;
  if exists (select 1 from public.profiles where lower(dg_id) = lower(trim(new_dg_id))) then raise exception 'That DG ID is already assigned'; end if;
  select id into selected_role_id from public.roles where organization_id = org_id and name = role_name and status = 'active';
  if selected_role_id is null then raise exception 'Selected role is not available'; end if;
  update auth.users set email_confirmed_at = coalesce(email_confirmed_at, now()), raw_user_meta_data = jsonb_set(coalesce(raw_user_meta_data, '{}'::jsonb), '{full_name}', to_jsonb(employee_name)), updated_at = now() where id = target_user_id;
  insert into public.profiles (id, organization_id, dg_id, full_name, email, initials, job_title, status, created_by)
  values (target_user_id, org_id, lower(trim(new_dg_id)), employee_name, lower(trim(login_email)), upper(left(regexp_replace(employee_name, '[^A-Za-z]', '', 'g'), 2)), role_name, 'active', auth.uid());
  insert into public.user_roles (user_id, role_id, is_primary) values (target_user_id, selected_role_id, true);
  insert into public.audit_logs (organization_id, actor_id, action, object_type, object_id, metadata) values (org_id, auth.uid(), 'employee_created', 'profile', target_user_id, jsonb_build_object('dgId', lower(trim(new_dg_id)), 'roleName', role_name));
  return target_user_id;
end;
$$;
revoke all on function public.provision_employee(uuid, text, text, text, text) from public;
grant execute on function public.provision_employee(uuid, text, text, text, text) to authenticated;

-- The owner creates confirmed Auth accounts directly so employee provisioning is
-- not subject to the public signup email throttle.
create or replace function private.create_employee_account(target_dg_id text, target_name text, target_email text, target_password text, target_role_name text)
returns jsonb language plpgsql security definer set search_path = public, auth, extensions
as $$
declare
  org_id uuid;
  selected_role_id uuid;
  new_user_id uuid := uuid_generate_v4();
  normalized_dg_id text := lower(trim(target_dg_id));
  normalized_email text := lower(trim(target_email));
  normalized_name text := trim(target_name);
begin
  org_id := public.current_org_id();
  if org_id is null then raise exception 'Workspace is not initialized'; end if;
  if normalized_dg_id !~ '^dg-[0-9]{4}$' or substring(normalized_dg_id from 4)::integer not between 1 and 10000 then raise exception 'DG ID must be between dg-0001 and dg-10000'; end if;
  if normalized_name is null or length(normalized_name) < 2 then raise exception 'Employee name is required'; end if;
  if normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'Enter a valid employee email'; end if;
  if target_password is null or length(target_password) < 10 then raise exception 'Password must be at least 10 characters'; end if;
  if exists (select 1 from public.profiles where lower(dg_id) = normalized_dg_id) then raise exception 'That DG ID is already assigned'; end if;
  if exists (select 1 from auth.users where lower(email) = normalized_email and deleted_at is null) then raise exception 'That email is already in use'; end if;
  select id into selected_role_id from public.roles where organization_id = org_id and name = target_role_name and status = 'active';
  if selected_role_id is null then raise exception 'Selected role is not available'; end if;

  insert into auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    confirmation_token, recovery_token, email_change_token_new,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    phone_change, phone_change_token, email_change_token_current,
    email_change_confirm_status, is_sso_user, is_anonymous
  ) values (
    new_user_id, 'authenticated', 'authenticated', normalized_email,
    extensions.crypt(target_password, extensions.gen_salt('bf')), now(),
    '', '', '',
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
    jsonb_build_object('sub', new_user_id::text, 'email', normalized_email, 'full_name', normalized_name, 'role_name', target_role_name, 'email_verified', true, 'phone_verified', false),
    now(), now(), '', '', '', 0, false, false
  );

  insert into auth.identities (user_id, provider_id, identity_data, provider, created_at, updated_at)
  values (new_user_id, new_user_id::text, jsonb_build_object('sub', new_user_id::text, 'email', normalized_email, 'full_name', normalized_name, 'email_verified', true, 'phone_verified', false), 'email', now(), now());
  insert into public.profiles (id, organization_id, dg_id, full_name, email, initials, job_title, status, created_by)
  values (new_user_id, org_id, normalized_dg_id, normalized_name, normalized_email, upper(left(regexp_replace(normalized_name, '[^A-Za-z]', '', 'g'), 2)), target_role_name, 'active', auth.uid());
  insert into public.user_roles (user_id, role_id, is_primary) values (new_user_id, selected_role_id, true);
  insert into public.audit_logs (organization_id, actor_id, action, object_type, object_id, metadata)
  values (org_id, auth.uid(), 'employee_created', 'profile', new_user_id, jsonb_build_object('dgId', normalized_dg_id, 'roleName', target_role_name, 'email', normalized_email));
  return jsonb_build_object('userId', new_user_id, 'dgId', normalized_dg_id, 'email', normalized_email);
exception when others then
  raise;
end;
$$;
revoke all on function private.create_employee_account(text, text, text, text, text) from public;
revoke all on function private.create_employee_account(text, text, text, text, text) from authenticated, anon;

create or replace function public.create_employee_account(new_dg_id text, employee_name text, login_email text, employee_password text, role_name text)
returns jsonb language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_org_admin() then raise exception 'Only the Main Admin can create employee accounts'; end if;
  return private.create_employee_account(new_dg_id, employee_name, login_email, employee_password, role_name);
end;
$$;
revoke all on function public.create_employee_account(text, text, text, text, text) from public;
grant execute on function public.create_employee_account(text, text, text, text, text) to authenticated;

create or replace function public.delete_employee_account(target_user_id uuid, confirmation text)
returns jsonb language plpgsql security definer set search_path = public, auth
as $$
declare
  org_id uuid;
  target_name text;
  target_dg_id text;
  is_admin boolean;
begin
  if confirmation <> 'DELETE' then raise exception 'Type DELETE to confirm account deletion'; end if;
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if target_user_id = auth.uid() then raise exception 'You cannot delete your own account'; end if;
  org_id := public.current_org_id();
  is_admin := public.is_org_admin();
  if not is_admin and not exists (
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid() and r.name in ('Team Lead', 'Technical Lead', 'Operations Lead')
  ) then raise exception 'Only a Main Admin or team lead can delete employee accounts'; end if;
  select full_name, dg_id into target_name, target_dg_id
  from public.profiles where id = target_user_id and organization_id = org_id;
  if target_name is null then raise exception 'Employee is not in your workspace'; end if;
  if exists (select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id where ur.user_id = target_user_id and r.name = 'Main Admin') then
    raise exception 'Main Admin accounts cannot be deleted from this screen';
  end if;
  if not is_admin and not exists (
    select 1 from public.team_members tm join public.teams t on t.id = tm.team_id
    where tm.user_id = target_user_id and t.organization_id = org_id and t.lead_id = auth.uid()
  ) then raise exception 'You can only delete employees from a team you lead'; end if;
  insert into public.audit_logs (organization_id, actor_id, action, object_type, object_id, metadata)
  values (org_id, auth.uid(), 'employee_deleted', 'profile', target_user_id, jsonb_build_object('dgId', target_dg_id, 'fullName', target_name));
  delete from auth.users where id = target_user_id;
  return jsonb_build_object('ok', true, 'message', target_name || ' was deleted');
end;
$$;
revoke all on function public.delete_employee_account(uuid, text) from public;
grant execute on function public.delete_employee_account(uuid, text) to authenticated;

-- Realtime publication for collaboration surfaces.
alter publication supabase_realtime add table public.tasks;
alter publication supabase_realtime add table public.task_comments;
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.attendance;
