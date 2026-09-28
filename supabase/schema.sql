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
  created_at timestamptz not null default now()
);

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

-- Realtime publication for collaboration surfaces.
alter publication supabase_realtime add table public.tasks;
alter publication supabase_realtime add table public.task_comments;
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.attendance;
