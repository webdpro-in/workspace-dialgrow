-- Attendance state changes must go through the validated RPC. This prevents
-- clients from fabricating a second check-in or check-out through REST.
drop policy if exists "own attendance insert" on public.attendance;
drop policy if exists "own attendance update" on public.attendance;
create policy "admins update attendance" on public.attendance for update to authenticated
using (organization_id = public.current_org_id() and public.is_org_admin())
with check (organization_id = public.current_org_id() and public.is_org_admin());
