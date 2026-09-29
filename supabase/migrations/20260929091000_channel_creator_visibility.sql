-- A creator must be able to receive the row from an insert().select().
-- The direct creator check avoids a snapshot edge case while the new row is
-- being returned before its first channel_members row exists.
drop policy if exists "visible channels" on public.channels;
create policy "visible channels" on public.channels
for select to authenticated
using (
  organization_id = public.current_org_id()
  and (
    access_scope = 'organization'
    or created_by = auth.uid()
    or public.can_access_channel(id, auth.uid())
  )
);
