import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };

async function sendCredentialEmail({ to, dgId, fullName, roleName, password }: { to: string; dgId: string; fullName: string; roleName: string; password: string }) {
  const apiKey = Deno.env.get('RESEND_API_KEY');
  if (!apiKey) return { sent: false, reason: 'RESEND_API_KEY is not configured' };
  const workspaceUrl = Deno.env.get('WORKSPACE_URL') || 'https://workspace.dialgrow.com';
  const from = Deno.env.get('DIALGROW_FROM_EMAIL') || 'DialGrow Workspace <onboarding@dialgrow.com>';
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from,
      to: [to],
      subject: 'Your DialGrow Workspace access',
      html: `<div style="font-family:Arial,sans-serif;max-width:560px;color:#132018"><h2>Welcome to DialGrow Workspace, ${fullName}</h2><p>Your Main Admin created an account for you.</p><p><strong>Role:</strong> ${roleName}</p><p><strong>Console:</strong> <a href="${workspaceUrl}">${workspaceUrl}</a></p><p><strong>DG ID:</strong> ${dgId}<br><strong>Password:</strong> ${password}<br><strong>Notification email:</strong> ${to}</p><p>Use your DG ID and password to sign in. Keep these details private.</p><p style="color:#6b7c70">DialGrow Workspace · People, work, knowledge and communication</p></div>`,
    }),
  });
  if (!response.ok) throw new Error(`Credential email failed: ${await response.text()}`);
  return { sent: true };
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const authHeader = request.headers.get('Authorization');
    if (!authHeader) throw new Error('Missing authorization header');
    const adminClient = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const callerClient = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authHeader } } });
    const { data: { user: caller } } = await callerClient.auth.getUser();
    if (!caller) throw new Error('Not authenticated');
    const { data: callerProfile, error: callerProfileError } = await adminClient.from('profiles').select('organization_id, employee_creation_limit').eq('id', caller.id).single();
    if (callerProfileError || !callerProfile?.organization_id) throw new Error('Your workspace profile is not initialized');
    const { data: callerRoles, error: callerRolesError } = await adminClient.from('user_roles').select('roles(name, dashboard_template, can_create_employees)').eq('user_id', caller.id);
    if (callerRolesError) throw callerRolesError;
    const roleRecords = (callerRoles || []).map((item: { roles?: { name?: string; dashboard_template?: string; can_create_employees?: boolean } }) => item.roles).filter(Boolean);
    const isMainAdmin = roleRecords.some((role) => role?.name === 'Main Admin');
    const leadRole = roleRecords.find((role) => ['Team Lead', 'Technical Lead', 'Operations Lead'].includes(role?.name || '') || role?.can_create_employees);
    if (!isMainAdmin && !leadRole) throw new Error('Only a Main Admin or team lead can create employee accounts');
    if (!isMainAdmin) {
      const { count: createdCount, error: countError } = await adminClient.from('profiles').select('id', { count: 'exact', head: true }).eq('organization_id', callerProfile.organization_id).eq('created_by', caller.id);
      if (countError) throw countError;
      const creationLimit = callerProfile.employee_creation_limit || 4;
      if ((createdCount || 0) >= creationLimit) throw new Error(`Employee creation limit reached (${creationLimit}). Request approval from Main Admin.`);
    }

    const { email: rawEmail, dgId: rawDgId, password, fullName, roleName, teamId } = await request.json();
    let dgId = rawDgId?.trim().toLowerCase();
    if (!dgId) {
      for (let attempt = 0; attempt < 20; attempt += 1) {
        const candidate = `dg-${String(Math.floor(Math.random() * 10000) + 1).padStart(4, '0')}`;
        const { data: candidateProfile } = await adminClient.from('profiles').select('id').eq('dg_id', candidate).maybeSingle();
        if (!candidateProfile) { dgId = candidate; break; }
      }
    }
    if (!dgId || !/^dg-\d{4}$/.test(dgId) || Number(dgId.slice(3)) < 1 || Number(dgId.slice(3)) > 10000) throw new Error('DG ID must be between dg-0001 and dg-10000');
    const email = rawEmail?.trim().toLowerCase() || `${dgId}@dialgrow.com`;
    if (!/^\S+@\S+\.\S+$/.test(email)) throw new Error('Enter a valid notification email or leave it blank');
    if (!password || password.length < 10) throw new Error('Temporary password must be at least 10 characters');
    if (!fullName || !roleName) throw new Error('Full name and role are required');
    const orgId = callerProfile.organization_id;
    const { data: targetRole, error: targetRoleError } = await adminClient.from('roles').select('id, name, dashboard_template').eq('organization_id', orgId).eq('name', roleName).eq('status', 'active').single();
    if (targetRoleError || !targetRole) throw new Error('Selected role is not available');
    if (!isMainAdmin && targetRole.name === 'Main Admin') throw new Error('Team leads cannot create Main Admin accounts');
    if (!isMainAdmin && !teamId) throw new Error('Select the team this employee will join');
    if (teamId) {
      const { data: team, error: teamError } = await adminClient.from('teams').select('id, organization_id, lead_id').eq('id', teamId).eq('organization_id', orgId).single();
      if (teamError || !team) throw new Error('Selected team is not in your workspace');
      if (!isMainAdmin && team.lead_id !== caller.id) throw new Error('You can only create employees for a team you lead');
    }
    const { data: existingProfile } = await adminClient.from('profiles').select('id').eq('dg_id', dgId).maybeSingle();
    if (existingProfile) throw new Error('That DG ID is already assigned. Choose another one.');

    const { data: created, error: createError } = await adminClient.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name: fullName, role_name: roleName, must_change_password: true } });
    if (createError) throw createError;
    const userId = created.user.id;
    try {
      const { error: profileError } = await adminClient.from('profiles').insert({ id: userId, organization_id: orgId, dg_id: dgId, full_name: fullName, email, initials: fullName.split(/\s+/).map((part: string) => part[0]).join('').slice(0, 2).toUpperCase(), job_title: roleName, status: 'active', created_by: caller.id });
      if (profileError) throw profileError;
      const { error: roleError } = await adminClient.from('user_roles').insert({ user_id: userId, role_id: targetRole.id, is_primary: true });
      if (roleError) throw roleError;
      if (teamId) {
        const { error: membershipError } = await adminClient.from('team_members').insert({ team_id: teamId, user_id: userId });
        if (membershipError) throw membershipError;
      }
    } catch (provisionError) {
      await adminClient.auth.admin.deleteUser(userId);
      throw provisionError;
    }
    await adminClient.from('audit_logs').insert({ organization_id: orgId, actor_id: caller.id, action: 'employee_created', object_type: 'profile', object_id: userId, metadata: { dgId, email, roleName } });
    const delivery = rawEmail ? await sendCredentialEmail({ to: email, dgId, fullName, roleName, password }) : { sent: false };
    return new Response(JSON.stringify({ ok: true, userId, dgId, email, emailSent: delivery.sent, message: delivery.sent ? 'Employee account created and credentials emailed' : 'Employee account created; share the DG ID and password securely' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Unable to create employee' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
