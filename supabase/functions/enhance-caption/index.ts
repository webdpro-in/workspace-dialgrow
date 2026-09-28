const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const apiKey = Deno.env.get('OPENAI_API_KEY');
    if (!apiKey) throw new Error('OPENAI_API_KEY is not configured');
    const { caption, audience } = await request.json();
    if (!caption?.trim()) throw new Error('Caption is required');
    const response = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'gpt-4.1-mini',
        input: `Rewrite this DialGrow social post caption so it feels human, specific, warm and useful. Keep the original meaning, avoid hype and do not invent facts. Audience: ${audience || 'employees'}. Return only the finished caption, with no quotation marks or explanation.\n\n${caption}`,
        max_output_tokens: 250,
      }),
    });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error?.message || 'Caption enhancement failed');
    const enhanced = payload.output_text || payload.output?.flatMap((item: { content?: { text?: string }[] }) => item.content || []).map((item: { text?: string }) => item.text || '').join('').trim();
    if (!enhanced) throw new Error('The AI response did not include a caption');
    return new Response(JSON.stringify({ caption: enhanced }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Unable to enhance caption' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
