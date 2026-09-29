import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const authHeader = request.headers.get('Authorization');
    if (!authHeader) throw new Error('Missing authorization header');

    const adminClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );
    const callerClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user: caller } } = await callerClient.auth.getUser();
    if (!caller) throw new Error('Not authenticated');

    const { targetUserId, confirmation } = await request.json();
    if (!targetUserId || confirmation !== 'DELETE') throw new Error('Type DELETE to confirm account deletion');
    if (targetUserId === caller.id) throw new Error('You cannot delete your own account from the workspace');

    const { data: callerProfile, error: callerProfileError } = await adminClient
      .from('profiles').select('organization_id').eq('id', caller.id).single();
    if (callerProfileError || !callerProfile?.organization_id) throw new Error('Your workspace profile is not initialized');

    const { data: callerRoles, error: callerRolesError } = await adminClient
      .from('user_roles').select('roles(name)').eq('user_id', caller.id);
    if (callerRolesError) throw callerRolesError;
    const roleNames = (callerRoles || [])
      .map((item: { roles?: { name?: string } }) => item.roles?.name)
      .filter(Boolean);
    const isMainAdmin = roleNames.includes('Main Admin');
    const isTeamLead = roleNames.some((name) => ['Team Lead', 'Technical Lead', 'Operations Lead'].includes(name || ''));
    if (!isMainAdmin && !isTeamLead) throw new Error('Only a Main Admin or team lead can delete employee accounts');

    const { data: targetProfile, error: targetProfileError } = await adminClient
      .from('profiles').select('id, organization_id, full_name, dg_id').eq('id', targetUserId).single();
    if (targetProfileError || !targetProfile || targetProfile.organization_id !== callerProfile.organization_id) {
      throw new Error('Employee is not in your workspace');
    }

    const { data: targetRoles } = await adminClient
      .from('user_roles').select('roles(name)').eq('user_id', targetUserId);
    if ((targetRoles || []).some((item: { roles?: { name?: string } }) => item.roles?.name === 'Main Admin')) {
      throw new Error('Main Admin accounts cannot be deleted from this screen');
    }

    if (!isMainAdmin) {
      const { data: ledTeams } = await adminClient
        .from('teams').select('id').eq('organization_id', callerProfile.organization_id).eq('lead_id', caller.id);
      const ledTeamIds = (ledTeams || []).map((team: { id: string }) => team.id);
      const { data: memberships } = await adminClient
        .from('team_members').select('team_id').eq('user_id', targetUserId).in('team_id', ledTeamIds.length ? ledTeamIds : ['00000000-0000-0000-0000-000000000000']);
      if (!memberships?.length) throw new Error('You can only delete employees from a team you lead');
    }

    await adminClient.from('audit_logs').insert({
      organization_id: callerProfile.organization_id,
      actor_id: caller.id,
      action: 'employee_deleted',
      object_type: 'profile',
      object_id: targetUserId,
      metadata: { dgId: targetProfile.dg_id, fullName: targetProfile.full_name },
    });

    const { error: deleteError } = await adminClient.auth.admin.deleteUser(targetUserId);
    if (deleteError) throw deleteError;

    return new Response(JSON.stringify({ ok: true, message: `${targetProfile.full_name} was deleted` }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Unable to delete employee' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
