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
  status public.role_status not null default 'draft',
  created_at timestamptz not null default now(),
  unique(organization_id, name)
);

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
  created_at timestamptz not null default now()
);

alter table public.profiles add column if not exists work_start_time time not null default '09:30';
alter table public.profiles add column if not exists work_end_time time not null default '18:30';
alter table public.profiles add column if not exists work_days smallint[] not null default '{1,2,3,4,5}';
alter table public.profiles add column if not exists timezone text not null default 'Asia/Kolkata';

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
  created_at timestamptz not null default now()
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
alter table public.projects enable row level security;
alter table public.tasks enable row level security;
alter table public.task_comments enable row level security;
alter table public.attendance enable row level security;
alter table public.channels enable row level security;
alter table public.messages enable row level security;
alter table public.documents enable row level security;
alter table public.training_courses enable row level security;
alter table public.training_assignments enable row level security;
alter table public.training_progress enable row level security;
alter table public.positions enable row level security;
alter table public.audit_logs enable row level security;
alter table public.user_roles enable row level security;
alter table public.announcements enable row level security;
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
  select lower(auth.jwt() ->> 'email') = 'business@dialgrow.com' and exists (
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid() and r.name = 'Main Admin'
  )
$$;

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
create policy "same organization roles" on public.roles for select to authenticated using (organization_id = public.current_org_id());
create policy "admin creates roles" on public.roles for insert to authenticated with check (organization_id = public.current_org_id() and public.is_org_admin());
create policy "admin updates roles" on public.roles for update to authenticated using (organization_id = public.current_org_id() and public.is_org_admin()) with check (organization_id = public.current_org_id() and public.is_org_admin());
create policy "own or admin role memberships" on public.user_roles for select to authenticated using (user_id = auth.uid() or public.is_org_admin());
create policy "admin assigns roles" on public.user_roles for insert to authenticated with check (public.is_org_admin());
create policy "admin updates role assignments" on public.user_roles for update to authenticated using (public.is_org_admin()) with check (public.is_org_admin());
create policy "same organization teams" on public.teams for select to authenticated using (organization_id = public.current_org_id());
create policy "own or admin attendance" on public.attendance for select to authenticated using (organization_id = public.current_org_id() and (user_id = auth.uid() or public.is_org_admin()));
create policy "own attendance insert" on public.attendance for insert to authenticated with check (organization_id = public.current_org_id() and user_id = auth.uid());
create policy "own attendance update" on public.attendance for update to authenticated using (organization_id = public.current_org_id() and (user_id = auth.uid() or public.is_org_admin()));
create policy "same organization tasks in scope" on public.tasks for select to authenticated using (organization_id = public.current_org_id() and (public.is_org_admin() or creator_id = auth.uid() or assignee_id = auth.uid() or reviewer_id = auth.uid() or exists (select 1 from public.team_members tm where tm.team_id = tasks.team_id and tm.user_id = auth.uid())));
create policy "scoped task creation" on public.tasks for insert to authenticated with check (organization_id = public.current_org_id() and creator_id = auth.uid());
create policy "scoped task updates" on public.tasks for update to authenticated using (organization_id = public.current_org_id() and (public.is_org_admin() or creator_id = auth.uid() or assignee_id = auth.uid() or reviewer_id = auth.uid()));
create policy "same organization task comments" on public.task_comments for select to authenticated using (exists (select 1 from public.tasks t where t.id = task_id and t.organization_id = public.current_org_id()));
create policy "scoped task comments" on public.task_comments for insert to authenticated with check (author_id = auth.uid() and exists (select 1 from public.tasks t where t.id = task_id and t.organization_id = public.current_org_id()));
create policy "same organization channels" on public.channels for select to authenticated using (organization_id = public.current_org_id());
create policy "admin creates channels" on public.channels for insert to authenticated with check (organization_id = public.current_org_id() and public.is_org_admin());
create policy "same organization messages" on public.messages for select to authenticated using (exists (select 1 from public.channels c where c.id = channel_id and c.organization_id = public.current_org_id()));
create policy "scoped message creation" on public.messages for insert to authenticated with check (author_id = auth.uid() and exists (select 1 from public.channels c where c.id = channel_id and c.organization_id = public.current_org_id()));
create policy "same organization documents" on public.documents for select to authenticated using (organization_id = public.current_org_id());
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
create policy "visible post recipients" on public.social_post_recipients for select to authenticated using (user_id = auth.uid() or public.is_org_admin());
create policy "admin assigns post recipients" on public.social_post_recipients for insert to authenticated with check (public.is_org_admin());
create policy "users update own post status" on public.social_post_recipients for update to authenticated using (user_id = auth.uid() or public.is_org_admin()) with check (user_id = auth.uid() or public.is_org_admin());

insert into storage.buckets (id, name, public)
values ('social-posts', 'social-posts', true)
on conflict (id) do update set public = true;

create policy "public can view social posters" on storage.objects for select using (bucket_id = 'social-posts');
create policy "admins upload social posters" on storage.objects for insert to authenticated with check (bucket_id = 'social-posts' and public.is_org_admin());
create policy "admins update social posters" on storage.objects for update to authenticated using (bucket_id = 'social-posts' and public.is_org_admin()) with check (bucket_id = 'social-posts' and public.is_org_admin());
create policy "admins delete social posters" on storage.objects for delete to authenticated using (bucket_id = 'social-posts' and public.is_org_admin());

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
  insert into public.roles (organization_id, name, layer, description, dashboard_template, visibility_scope, status, responsibilities)
  values
    (org_id, 'Main Admin', 'System', 'Organization-wide control center with full configuration, security and audit access.', 'admin', 'organization', 'active', array['Manage people, roles and teams', 'Configure permissions and policies', 'Review analytics and audit logs']),
    (org_id, 'Team Lead', 'Management', 'Owns a team''s priorities, assignments, reviews and workload.', 'team', 'team', 'active', array['Create and assign team tasks', 'Review outputs and request changes', 'Track team training and workload']),
    (org_id, 'Technical Lead', 'Management', 'Guides technical teams and intern groups with technical task metadata.', 'technical', 'technical', 'active', array['Manage technical work', 'Review projects and coding tasks', 'Support technical training']),
    (org_id, 'Operations Lead', 'Management', 'Runs daily execution, attendance workflows and operational exceptions.', 'operations', 'operations', 'active', array['Monitor check-ins and exceptions', 'Assign operational work', 'Report on completion trends']),
    (org_id, 'Full Stack Developer', 'Technical', 'Executes product work and contributes to technical delivery.', 'technical', 'team', 'active', array['Own technical tasks', 'Attach code and resources', 'Submit work for review']),
    (org_id, 'Customer Success', 'Business', 'Connects customer context to tasks, handoffs and growth outcomes.', 'employee', 'team', 'active', array['Manage customer tasks', 'Share permitted documents', 'Coordinate account follow-ups'])
  on conflict (organization_id, name) do update set description = excluded.description, responsibilities = excluded.responsibilities, status = 'active';
  insert into public.profiles (id, organization_id, full_name, email, initials, job_title, timezone)
  values (auth.uid(), org_id, coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', 'Durga Prashad'), lower(auth.jwt() ->> 'email'), 'DP', 'Main Admin', 'Asia/Kolkata')
  on conflict (id) do update set organization_id = excluded.organization_id, job_title = 'Main Admin';
  select id into admin_role_id from public.roles where organization_id = org_id and name = 'Main Admin';
  insert into public.user_roles (user_id, role_id, is_primary) values (auth.uid(), admin_role_id, true) on conflict (user_id, role_id) do update set is_primary = true;
  insert into public.channels (organization_id, name, description, channel_type) values (org_id, 'general', 'DialGrow-wide updates and announcements', 'announcement') on conflict do nothing;
  return org_id;
end;
$$;

grant execute on function public.bootstrap_dialgrow_workspace() to authenticated;

-- Realtime publication for collaboration surfaces.
alter publication supabase_realtime add table public.tasks;
alter publication supabase_realtime add table public.task_comments;
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.attendance;
