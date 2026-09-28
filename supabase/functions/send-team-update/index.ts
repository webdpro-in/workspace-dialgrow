import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };
const updates = [
  'Quick pulse for today: keep one priority visible, close one open loop, and leave the next person better context than you found it.',
  'Team note: if work is blocked, bring the missing context into the task or group before the end of the day. Visibility is a form of momentum.',
  'Today\'s rhythm: protect your focus window, share progress early, and use the workspace to make the handoff easy for the next person.',
];

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const payload = await request.json().catch(() => ({}));
    const fridayPrompt = Boolean(payload.fridayPrompt);
    const organizations = payload.organizationId ? [{ id: payload.organizationId }] : (await client.from('organizations').select('id')).data || [];
    if (!organizations.length) throw new Error('No DialGrow organizations are available');
    const body = fridayPrompt ? 'Friday check-in: what moved forward this week, what is still blocked, and what is the one thing your team should carry into next week?' : updates[Math.floor(Math.random() * updates.length)];
    for (const organization of organizations) {
      const { data: channel } = await client.from('channels').select('id').eq('organization_id', organization.id).eq('channel_type', 'announcement').limit(1).maybeSingle();
      if (!channel) continue;
      const { error } = await client.from('messages').insert({ channel_id: channel.id, body, author_id: null });
      if (error) throw error;
      await client.from('announcements').insert({ organization_id: organization.id, author_name: 'Priya Sharma', title: fridayPrompt ? 'Weekly update prompt' : 'Updated for today', body, scheduled_for: new Date().toISOString() });
    }
    return new Response(JSON.stringify({ ok: true, organizations: organizations.length, author: 'Priya Sharma' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Unable to send update' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
