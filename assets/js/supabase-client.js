// =========================================================
// RAIZEY STORE — Supabase Client
// =========================================================
const SUPABASE_URL = "https://rglbfizqolrenwfsndyv.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJnbGJmaXpxb2xyZW53ZnNuZHl2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxNDY4NzMsImV4cCI6MjA5ODcyMjg3M30.bJywsPvgXPdsNOZlVTIwYHz3Z2zcobwinGuUXAb5ev4";

const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function getExchangeRate() {
  const { data, error } = await supabaseClient
    .from('settings')
    .select('value')
    .eq('key', 'usd_to_sdg_rate')
    .single();
  if (error || !data) return 0;
  return parseFloat(data.value) || 0;
}

function formatSDG(amount) {
  return new Intl.NumberFormat('ar-SD').format(Math.round(amount));
}
