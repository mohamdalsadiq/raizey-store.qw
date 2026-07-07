// =========================================================
// RAIZEY STORE — Supabase Client
// =========================================================
const SUPABASE_URL = "https://rglbfizqolrenwfsndyv.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJnbGJmaXpxb2xyZW53ZnNuZHl2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxNDY4NzMsImV4cCI6MjA5ODcyMjg3M30.bJywsPvgXPdsNOZlVTIwYHz3Z2zcobwinGuUXAb5ev4";

const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// دالة مساعدة: جلب سعر الصرف مع هامش الربح مطبق تلقائياً
async function getExchangeRate() {
  const { data, error } = await supabaseClient
    .from('settings')
    .select('key, value')
    .in('key', ['usd_to_sdg_rate', 'profit_margin_percent']);

  if (error || !data) return 0;

  const map = {};
  data.forEach(row => { map[row.key] = parseFloat(row.value) || 0; });

  const rate = map.usd_to_sdg_rate || 0;
  const margin = map.profit_margin_percent || 0;

  return rate * (1 + margin / 100);
}

// دالة مساعدة: تنسيق السعر بالجنيه
function formatSDG(amount) {
  return new Intl.NumberFormat('ar-SD').format(Math.round(amount));
}
