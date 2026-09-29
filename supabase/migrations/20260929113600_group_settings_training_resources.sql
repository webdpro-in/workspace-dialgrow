-- Group settings and private, group-scoped learning resources.
-- Teams and chat groups remain compatible with the existing schema, while the
-- channel is the single visibility boundary for conversations and training.

create table if not exists public.training_resources (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  channel_id uuid not null references public.channels(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text not null default '',
  resource_type text not null default 'document' check (resource_type in ('document', 'video', 'link', 'colab')),
  url text,
  storage_path text,
  file_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint training_resources_has_source check (nullif(trim(coalesce(url, '')), '') is not null or nullif(trim(coalesce(storage_path, '')), '') is not null)
);

create index if not exists training_resources_channel_created_at_idx
  on public.training_resources (channel_id, created_at desc);

alter table public.training_resources enable row level security;
grant select, insert, update, delete on public.training_resources to authenticated;

drop policy if exists "visible group training resources" on public.training_resources;
drop policy if exists "group leaders create training resources" on public.training_resources;
drop policy if exists "owners update training resources" on public.training_resources;
drop policy if exists "owners delete training resources" on public.training_resources;

create policy "visible group training resources" on public.training_resources
for select to authenticated
using (
  organization_id = public.current_org_id()
  and (
    public.is_org_admin()
    or created_by = auth.uid()
    or public.can_access_channel(channel_id, auth.uid())
  )
);

create policy "group leaders create training resources" on public.training_resources
for insert to authenticated
with check (
  organization_id = public.current_org_id()
  and created_by = auth.uid()
  and (
    public.can_manage_channel(channel_id)
    or (public.has_role_capability('teams') and public.can_access_channel(channel_id, auth.uid()))
  )
);

create policy "owners update training resources" on public.training_resources
for update to authenticated
using (organization_id = public.current_org_id() and (public.is_org_admin() or created_by = auth.uid()))
with check (organization_id = public.current_org_id() and (public.is_org_admin() or created_by = auth.uid()));

create policy "owners delete training resources" on public.training_resources
for delete to authenticated
using (organization_id = public.current_org_id() and (public.is_org_admin() or created_by = auth.uid()));

drop policy if exists "members read team files" on storage.objects;
create policy "members read team files" on storage.objects for select to authenticated using (
  bucket_id = 'team-files'
  and name like (public.current_org_id()::text || '/%')
  and (
    exists (
      select 1 from public.documents d
      where d.storage_path = name
        and (d.channel_id is null or public.can_access_channel(d.channel_id, auth.uid()))
    )
    or exists (
      select 1 from public.training_resources tr
      where tr.storage_path = name
        and (public.is_org_admin() or tr.created_by = auth.uid() or public.can_access_channel(tr.channel_id, auth.uid()))
    )
  )
);

drop policy if exists "owners delete team files" on storage.objects;
create policy "owners delete team files" on storage.objects for delete to authenticated using (
  bucket_id = 'team-files'
  and (
    public.is_org_admin()
    or name like (public.current_org_id()::text || '/' || auth.uid()::text || '/%')
    or exists (select 1 from public.documents d where d.storage_path = name and d.owner_id = auth.uid())
    or exists (select 1 from public.training_resources tr where tr.storage_path = name and tr.created_by = auth.uid())
  )
);
