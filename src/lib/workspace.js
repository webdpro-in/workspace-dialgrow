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
    supabase.from('user_roles').select('is_primary, roles(id, name, layer, description, dashboard_template, responsibilities, visibility_scope, can_create_roles, can_create_teams, can_create_employees, metadata)').eq('user_id', user.id),
  ]);

  if (profileResult.error) throw profileResult.error;
  if (membershipsResult.error) throw membershipsResult.error;
  const profile = profileResult.data;
  const memberships = membershipsResult.data || [];
  const role = memberships.find((item) => item.is_primary)?.roles || memberships[0]?.roles || roleDefaults[user.user_metadata?.role_name] || roleDefaults['Customer Success'];
  const attendanceQuery = role?.name === 'Main Admin'
    ? supabase.from('attendance').select('*').order('work_date', { ascending: false }).order('check_in_at', { ascending: false }).limit(500)
    : supabase.from('attendance').select('*').eq('user_id', user.id).order('work_date', { ascending: false }).limit(90);
  const messagesQuery = role?.name === 'Main Admin'
    ? supabase.from('messages').select('*').order('created_at', { ascending: false }).limit(500)
    : Promise.resolve({ data: [], error: null });

  const [tasksResult, teamsResult, channelsResult, attendanceResult, auditResult, rolesResult, membersResult, memberRolesResult, teamMembersResult, channelMembersResult, postsResult, documentsResult, trainingResourcesResult, updatesResult, creationRequestsResult, messagesResult] = await Promise.all([
    supabase.from('tasks').select('*').order('created_at', { ascending: false }).limit(100),
    supabase.from('teams').select('*').order('name'),
    supabase.from('channels').select('*').order('created_at'),
    attendanceQuery,
    supabase.from('audit_logs').select('*').eq('actor_id', user.id).eq('action', 'login').order('created_at', { ascending: false }).limit(8),
    supabase.from('roles').select('*').order('name'),
    supabase.from('profiles').select('id, dg_id, full_name, email, job_title, avatar_color, status, employee_creation_limit, created_by').order('full_name'),
    supabase.from('user_roles').select('user_id, is_primary, roles(id, name)').eq('is_primary', true),
    supabase.from('team_members').select('team_id, user_id'),
    supabase.from('channel_members').select('channel_id, user_id'),
    supabase.from('social_posts').select('*').order('created_at', { ascending: false }).limit(50),
    supabase.from('documents').select('*').order('created_at', { ascending: false }).limit(100),
    supabase.from('training_resources').select('*').order('created_at', { ascending: false }).limit(100),
    supabase.from('team_updates').select('*').order('created_at', { ascending: false }).limit(100),
    supabase.from('employee_creation_requests').select('*').order('created_at', { ascending: false }).limit(50),
    messagesQuery,
  ]);

  const firstError = [tasksResult, teamsResult, channelsResult, attendanceResult, auditResult, rolesResult, membersResult, memberRolesResult, teamMembersResult, channelMembersResult, postsResult, documentsResult, trainingResourcesResult, updatesResult, creationRequestsResult, messagesResult].find((result) => result.error);
  if (firstError) throw firstError.error;

  const members = (membersResult.data || []).map((member) => ({ ...member, role: memberRolesResult.data?.find((item) => item.user_id === member.id)?.roles || null }));
  const memberById = new Map(members.map((member) => [member.id, member]));
  const teamById = new Map((teamsResult.data || []).map((team) => [team.id, team]));
  const attendanceHistory = attendanceResult.data || [];
  return {
    profile: { ...(profile || {}), full_name: profile?.full_name || user.user_metadata?.full_name || user.email?.split('@')[0] || 'Workspace member', email: user.email, role },
    tasks: (tasksResult.data || []).map((task) => ({ ...task, creator: memberById.get(task.creator_id) || null, assignee: memberById.get(task.assignee_id) || null, team_name: teamById.get(task.team_id)?.name || null })),
    teams: teamsResult.data || [],
    channels: (channelsResult.data || []).map((channel) => ({ ...channel, display_name: channel.name?.toLowerCase() === 'general' ? 'Campfire' : channel.name })),
    attendance: attendanceHistory.find((entry) => entry.user_id === user.id) || null,
    attendanceHistory,
    logins: auditResult.data || [],
    roles: rolesResult.data || [],
    members,
    teamMembers: teamMembersResult.data || [],
    channelMembers: channelMembersResult.data || [],
    posts: postsResult.data || [],
    documents: documentsResult.data || [],
    trainingResources: (trainingResourcesResult.data || []).map((resource) => ({
      ...resource,
      group: (channelsResult.data || []).find((channel) => channel.id === resource.channel_id) || null,
      author: memberById.get(resource.created_by) || null,
    })),
    updates: updatesResult.data || [],
    creationRequests: creationRequestsResult.data || [],
    messages: messagesResult.data || [],
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

export async function updateAttendance({ action, sessionId }) {
  if (!supabase) throw new Error('Supabase is not configured.');
  return supabase.rpc('record_attendance_event', { action, timezone_name: Intl.DateTimeFormat().resolvedOptions().timeZone, event_session_id: sessionId });
}

export async function createTask({ organizationId, creatorId, title, description, priority, assigneeId, dueDate, noteColor, repeatRule, teamId }) {
  if (!supabase) throw new Error('Supabase is not configured.');
  return supabase.from('tasks').insert({ organization_id: organizationId, creator_id: creatorId, assignee_id: assigneeId || creatorId, team_id: teamId || null, reference: `DG-${Date.now().toString().slice(-6)}`, title, description: description || '', priority: priority || 'medium', due_date: dueDate || null, repeat_rule: repeatRule || 'once', note_color: noteColor || 'sun', status: 'assigned', task_type: 'operations', progress: 0 }).select().single();
}

export async function sendMessage({ channelId, authorId, body }) {
  if (!supabase) throw new Error('Supabase is not configured.');
  return supabase.from('messages').insert({ channel_id: channelId, author_id: authorId, body }).select().single();
}
