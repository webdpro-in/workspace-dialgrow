import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };

async function sendCredentialEmail({ to, fullName, roleName, password }: { to: string; fullName: string; roleName: string; password: string }) {
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
      html: `<div style="font-family:Arial,sans-serif;max-width:560px;color:#132018"><h2>Welcome to DialGrow Workspace, ${fullName}</h2><p>Your Main Admin created an account for you.</p><p><strong>Role:</strong> ${roleName}</p><p><strong>Console:</strong> <a href="${workspaceUrl}">${workspaceUrl}</a></p><p><strong>Email:</strong> ${to}<br><strong>Temporary password:</strong> ${password}</p><p>Please sign in and change this temporary password immediately. Keep these details private.</p><p style="color:#6b7c70">DialGrow Workspace · People, work, knowledge and communication</p></div>`,
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
    const { data: callerProfile } = await adminClient.from('profiles').select('organization_id, user_roles(is_primary, roles(name))').eq('id', caller.id).single();
    const isAdmin = callerProfile?.user_roles?.some((item: { roles?: { name?: string } }) => item.roles?.name === 'Main Admin');
    if (caller.email?.toLowerCase() !== 'business@dialgrow.com' || !isAdmin) throw new Error('Only the Main Admin owner can create employee accounts');

    const { email: rawEmail, password, fullName, roleName, teamId } = await request.json();
    const email = rawEmail?.trim().toLowerCase();
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
    const delivery = await sendCredentialEmail({ to: email, fullName, roleName, password });
    return new Response(JSON.stringify({ ok: true, userId, emailSent: delivery.sent, message: delivery.sent ? 'Employee account created and credentials emailed' : 'Employee account created; configure RESEND_API_KEY to email credentials' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Unable to create employee' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
