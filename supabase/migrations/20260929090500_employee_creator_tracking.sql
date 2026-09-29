-- Keep the SQL fallback employee-creation path aligned with the Edge Function.
-- The creator is recorded so per-lead employee limits and admin approvals work
-- regardless of which provisioning path the client uses.
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
  insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, confirmation_token, recovery_token, email_change_token_new, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, phone_change, phone_change_token, email_change_token_current, email_change_confirm_status, is_sso_user, is_anonymous)
  values (new_user_id, 'authenticated', 'authenticated', normalized_email, extensions.crypt(target_password, extensions.gen_salt('bf')), now(), '', '', '', jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')), jsonb_build_object('sub', new_user_id::text, 'email', normalized_email, 'full_name', normalized_name, 'role_name', target_role_name, 'email_verified', true, 'phone_verified', false), now(), now(), '', '', '', 0, false, false);
  insert into auth.identities (user_id, provider_id, identity_data, provider, created_at, updated_at)
  values (new_user_id, new_user_id::text, jsonb_build_object('sub', new_user_id::text, 'email', normalized_email, 'full_name', normalized_name, 'email_verified', true, 'phone_verified', false), 'email', now(), now());
  insert into public.profiles (id, organization_id, dg_id, full_name, email, initials, job_title, status, created_by)
  values (new_user_id, org_id, normalized_dg_id, normalized_name, normalized_email, upper(left(regexp_replace(normalized_name, '[^A-Za-z]', '', 'g'), 2)), target_role_name, 'active', auth.uid());
  insert into public.user_roles (user_id, role_id, is_primary) values (new_user_id, selected_role_id, true);
  insert into public.audit_logs (organization_id, actor_id, action, object_type, object_id, metadata)
  values (org_id, auth.uid(), 'employee_created', 'profile', new_user_id, jsonb_build_object('dgId', normalized_dg_id, 'roleName', target_role_name, 'email', normalized_email));
  return jsonb_build_object('userId', new_user_id, 'dgId', normalized_dg_id, 'email', normalized_email);
end;
$$;
