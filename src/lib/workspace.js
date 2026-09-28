import { supabase } from './supabase';

export const roleDefaults = {
  'Main Admin': { layer: 'System', dashboard: 'admin', description: 'Organization-wide control center with full configuration, security and audit access.' },
  'Team Lead': { layer: 'Management', dashboard: 'team', description: 'Owns a team\'s priorities, assignments, reviews and workload.' },
  'Technical Lead': { layer: 'Management', dashboard: 'technical', description: 'Guides technical teams and intern groups with technical task metadata.' },
  'Operations Lead': { layer: 'Management', dashboard: 'operations', description: 'Runs daily execution, attendance workflows and operational exceptions.' },
  'Full Stack Developer': { layer: 'Technical', dashboard: 'technical', description: 'Executes product work and contributes to technical delivery.' },
  'Customer Success': { layer: 'Business', dashboard: 'business', description: 'Connects customer context to tasks, handoffs and growth outcomes.' },
};

export async function loadWorkspace(user) {
  if (!supabase) throw new Error('Supabase is not configured. Add the project URL and publishable key.');

  const [profileResult, membershipsResult] = await Promise.all([
    supabase.from('profiles').select('*').eq('id', user.id).maybeSingle(),
    supabase.from('user_roles').select('is_primary, roles(id, name, layer, description, dashboard_template, responsibilities, visibility_scope)').eq('user_id', user.id),
  ]);

  if (profileResult.error) throw profileResult.error;
  if (membershipsResult.error) throw membershipsResult.error;
  const profile = profileResult.data;
  const memberships = membershipsResult.data || [];
  const role = memberships.find((item) => item.is_primary)?.roles || memberships[0]?.roles || roleDefaults[user.user_metadata?.role_name] || roleDefaults['Customer Success'];

  const [tasksResult, teamsResult, channelsResult, attendanceResult, auditResult, rolesResult, membersResult, memberRolesResult, postsResult] = await Promise.all([
    supabase.from('tasks').select('*').order('created_at', { ascending: false }).limit(100),
    supabase.from('teams').select('*').order('name'),
    supabase.from('channels').select('*').order('created_at'),
    supabase.from('attendance').select('*').eq('user_id', user.id).order('created_at', { ascending: false }).limit(1).maybeSingle(),
    supabase.from('audit_logs').select('*').eq('actor_id', user.id).eq('action', 'login').order('created_at', { ascending: false }).limit(8),
    supabase.from('roles').select('*').order('name'),
    supabase.from('profiles').select('id, full_name, email, job_title, avatar_color, status').order('full_name'),
    supabase.from('user_roles').select('user_id, is_primary, roles(id, name)').eq('is_primary', true),
    supabase.from('social_posts').select('*').order('created_at', { ascending: false }).limit(50),
  ]);

  const firstError = [tasksResult, teamsResult, channelsResult, attendanceResult, auditResult, rolesResult, membersResult, memberRolesResult, postsResult].find((result) => result.error);
  if (firstError) throw firstError.error;

  return {
    profile: { ...(profile || {}), full_name: profile?.full_name || user.user_metadata?.full_name || user.email?.split('@')[0] || 'Workspace member', email: user.email, role },
    tasks: tasksResult.data || [],
    teams: teamsResult.data || [],
    channels: channelsResult.data || [],
    attendance: attendanceResult.data || null,
    logins: auditResult.data || [],
    roles: rolesResult.data || [],
    members: (membersResult.data || []).map((member) => ({ ...member, role: memberRolesResult.data?.find((item) => item.user_id === member.id)?.roles || null })),
    posts: postsResult.data || [],
  };
}

export async function recordLogin(user, organizationId) {
  if (!supabase || !organizationId) return;
  await supabase.from('audit_logs').insert({
    organization_id: organizationId,
    actor_id: user.id,
    action: 'login',
    object_type: 'session',
    metadata: { login_at: new Date().toISOString(), timezone: Intl.DateTimeFormat().resolvedOptions().timeZone },
  });
}

export async function updateAttendance({ userId, organizationId, status, sessionId }) {
  if (!supabase) throw new Error('Supabase is not configured.');
  const { data: existing } = await supabase.from('attendance').select('id').eq('user_id', userId).eq('status', 'working').order('created_at', { ascending: false }).limit(1).maybeSingle();
  if (status === 'working' && existing?.id) return supabase.from('attendance').update({ status, check_in_at: new Date().toISOString(), session_id: sessionId }).eq('id', existing.id).select().single();
  return supabase.from('attendance').insert({ organization_id: organizationId, user_id: userId, status, check_in_at: status === 'working' ? new Date().toISOString() : null, check_out_at: status === 'checked_out' ? new Date().toISOString() : null, timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, session_id: sessionId }).select().single();
}

export async function createTask({ organizationId, creatorId, title, description, priority, assigneeId }) {
  if (!supabase) throw new Error('Supabase is not configured.');
  return supabase.from('tasks').insert({ organization_id: organizationId, creator_id: creatorId, assignee_id: assigneeId || creatorId, reference: `DG-${Date.now().toString().slice(-6)}`, title, description, priority, status: 'assigned', task_type: 'operations', progress: 0 }).select().single();
}

export async function sendMessage({ channelId, authorId, body }) {
  if (!supabase) throw new Error('Supabase is not configured.');
  return supabase.from('messages').insert({ channel_id: channelId, author_id: authorId, body }).select().single();
}
