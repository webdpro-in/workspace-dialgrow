import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const authHeader = request.headers.get('Authorization');
    if (!authHeader) throw new Error('Missing authorization header');
    const adminClient = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const callerClient = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authHeader } } });
    const { data: { user: caller } } = await callerClient.auth.getUser();
    if (!caller) throw new Error('Not authenticated');
    const { data: callerProfile } = await adminClient.from('profiles').select('organization_id, user_roles(is_primary, roles(name))').eq('id', caller.id).single();
    const isAdmin = callerProfile?.user_roles?.some((item: { roles?: { name?: string } }) => ['Main Admin', 'Admin', 'Super Admin'].includes(item.roles?.name || ''));
    if (!isAdmin) throw new Error('Only an organization admin can create employee accounts');

    const { email, password, fullName, roleName, teamId } = await request.json();
    if (!email?.endsWith('@dialgrow.com')) throw new Error('Employee email must use the @dialgrow.com domain');
    if (!password || password.length < 10) throw new Error('Temporary password must be at least 10 characters');
    if (!fullName || !roleName) throw new Error('Full name and role are required');

    const { data: created, error: createError } = await adminClient.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name: fullName, role_name: roleName, must_change_password: true } });
    if (createError) throw createError;
    const userId = created.user.id;
    const orgId = callerProfile.organization_id;
    await adminClient.from('profiles').insert({ id: userId, organization_id: orgId, full_name: fullName, email, initials: fullName.split(/\s+/).map((part: string) => part[0]).join('').slice(0, 2).toUpperCase(), job_title: roleName, status: 'active' });
    const { data: role } = await adminClient.from('roles').select('id').eq('organization_id', orgId).eq('name', roleName).single();
    if (role) await adminClient.from('user_roles').insert({ user_id: userId, role_id: role.id, is_primary: true });
    if (teamId) await adminClient.from('team_members').insert({ team_id: teamId, user_id: userId });
    await adminClient.from('audit_logs').insert({ organization_id: orgId, actor_id: caller.id, action: 'employee_created', object_type: 'profile', object_id: userId, metadata: { email, roleName } });
    return new Response(JSON.stringify({ ok: true, userId, message: 'Employee account created' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Unable to create employee' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
