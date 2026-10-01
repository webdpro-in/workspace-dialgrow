-- Any authenticated workspace member can create a common or group sticky note.
-- Visibility remains scoped by the existing task SELECT policy.
create or replace function public.can_create_common_note()
returns boolean language sql stable security definer set search_path = public
as $$
  select auth.uid() is not null and public.current_org_id() is not null
$$;
revoke all on function public.can_create_common_note() from public, anon;
grant execute on function public.can_create_common_note() to authenticated;

drop policy if exists "scoped task creation" on public.tasks;
create policy "scoped task creation" on public.tasks
for insert to authenticated
with check (
  organization_id = public.current_org_id()
  and creator_id = auth.uid()
  and (
    team_id is null
    or exists (
      select 1
      from public.teams t
      where t.id = tasks.team_id
        and t.organization_id = public.current_org_id()
    )
  )
);
