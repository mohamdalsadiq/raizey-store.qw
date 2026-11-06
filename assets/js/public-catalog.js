/* Public reads deliberately carry the published anon key, never the visitor session. */
(function () {
  'use strict';
  if (window.MeemPublicCatalog) return;
  window.MeemPublicCatalog = Object.freeze({
    async get(table, query) {
      if (!['store_sections', 'categories', 'products', 'settings'].includes(table)) throw new Error('invalid_public_table');
      const url = new URL('/rest/v1/' + table, window.SUPABASE_URL);
      url.search = new URLSearchParams(query).toString();
      const response = await fetch(url, {
        headers: { apikey: window.SUPABASE_ANON_KEY, Authorization: 'Bearer ' + window.SUPABASE_ANON_KEY },
        credentials: 'omit', signal: AbortSignal.timeout(10000)
      });
      if (!response.ok) throw new Error('public_catalog_unavailable');
      return response.json();
    },
    async rate() {
      const rows = await this.get('settings', {select:'key,value',key:'in.(usd_to_sdg_rate,profit_margin_percent)'});
      const settings = Object.fromEntries(rows.map(row=>[row.key, Number(row.value)]));
      const rate = settings.usd_to_sdg_rate * (1 + (settings.profit_margin_percent || 0) / 100);
      if (!Number.isFinite(rate) || rate <= 0) throw new Error('exchange_rate_unavailable');
      return rate;
    }
  });
})();
