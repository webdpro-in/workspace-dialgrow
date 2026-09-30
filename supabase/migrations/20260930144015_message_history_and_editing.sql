-- WhatsApp-style message controls and join-time history boundaries.
alter table public.team_members
  add column if not exists joined_at timestamptz not null default now();

-- Existing team members keep their current history. New memberships start at
-- the insert time and therefore cannot read messages from before they joined.
update public.team_members tm
set joined_at = coalesce(
  (
    select min(m.created_at)
    from public.messages m
    join public.channels c on c.id = m.channel_id
    where c.team_id = tm.team_id
  ),
  tm.joined_at
);

alter table public.messages add column if not exists edited_at timestamptz;
alter table public.messages replica identity full;
grant select, insert, update, delete on public.messages to authenticated;

create or replace function public.can_view_message(
  message_channel_id uuid,
  message_created_at timestamptz,
  viewer_uuid uuid default auth.uid()
)
returns boolean
language sql stable security definer set search_path = public
as $$
  select viewer_uuid is not null
    and viewer_uuid = auth.uid()
    and exists (
      select 1
      from public.profiles viewer
      join public.channels c on c.id = message_channel_id
        and c.organization_id = viewer.organization_id
      where viewer.id = viewer_uuid
        and (
          public.is_org_admin()
          or c.created_by = viewer_uuid
          or (
            c.access_scope = 'organization'
            and message_created_at >= greatest(c.created_at, viewer.created_at)
          )
          or exists (
            select 1
            from public.channel_members cm
            where cm.channel_id = c.id
              and cm.user_id = viewer_uuid
              and message_created_at >= cm.created_at
          )
          or exists (
            select 1
            from public.team_members tm
            where tm.team_id = c.team_id
              and tm.user_id = viewer_uuid
              and message_created_at >= tm.joined_at
          )
        )
    )
$$;

revoke all on function public.can_view_message(uuid, timestamptz, uuid) from public;
grant execute on function public.can_view_message(uuid, timestamptz, uuid) to authenticated;

drop policy if exists "same organization messages" on public.messages;
drop policy if exists "visible messages" on public.messages;
drop policy if exists "scoped message creation" on public.messages;
drop policy if exists "authors update messages" on public.messages;
drop policy if exists "authors delete messages" on public.messages;

create policy "visible messages" on public.messages
for select to authenticated
using (public.can_view_message(channel_id, created_at, auth.uid()));

create policy "scoped message creation" on public.messages
for insert to authenticated
with check (
  author_id = auth.uid()
  and public.can_access_channel(channel_id, auth.uid())
);

create policy "authors update messages" on public.messages
for update to authenticated
using (
  public.can_access_channel(channel_id, auth.uid())
  and (author_id = auth.uid() or public.is_org_admin())
)
with check (
  public.can_access_channel(channel_id, auth.uid())
  and (author_id = auth.uid() or public.is_org_admin())
);

create policy "authors delete messages" on public.messages
for delete to authenticated
using (
  public.can_access_channel(channel_id, auth.uid())
  and (author_id = auth.uid() or public.is_org_admin())
);
