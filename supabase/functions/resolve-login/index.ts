import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const { dgId: rawDgId } = await request.json();
    const dgId = rawDgId?.trim().toLowerCase();
    if (!dgId || !/^dg-\d{4}$/.test(dgId) || Number(dgId.slice(3)) < 1 || Number(dgId.slice(3)) > 10000) throw new Error('Enter a valid DG ID between dg-0001 and dg-10000');
    const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: profile, error } = await client.from('profiles').select('email').eq('dg_id', dgId).maybeSingle();
    if (error) throw error;
    if (!profile?.email) throw new Error('We could not find that DG ID');
    return new Response(JSON.stringify({ email: profile.email }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Unable to resolve DG ID' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
