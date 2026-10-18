(function () {
  'use strict';
  const client = window.supabaseClient;
  const error = document.getElementById('error');
  const button = document.getElementById('verify');
  let factorId = null;
  function finish() {
    let target = 'index.html';
    try {
      const saved = sessionStorage.getItem('meem_mfa_return');
      sessionStorage.removeItem('meem_mfa_return');
      const url = new URL(saved || target, location.origin);
      if (url.origin === location.origin && !url.pathname.endsWith('/mfa.html')) target = url.href;
    } catch (_) {}
    location.replace(target);
  }
  async function init() {
    try {
      if (!client?.auth?.mfa) throw new Error('unavailable');
      const { data: session } = await client.auth.getSession();
      if (!session?.session) { location.replace('login.html'); return; }
      const { data: aal, error: aalError } = await client.auth.mfa.getAuthenticatorAssuranceLevel();
      if (aalError) throw aalError;
      if (aal?.currentLevel === 'aal2' || aal?.nextLevel !== 'aal2') { finish(); return; }
      const { data, error: factorsError } = await client.auth.mfa.listFactors();
      if (factorsError) throw factorsError;
      factorId = (data?.totp || []).find(f => f.status === 'verified')?.id || null;
      if (!factorId) throw new Error('factor_unavailable');
    } catch (_) { error.textContent = 'تعذر تجهيز التحقق بخطوتين. أعد المحاولة أو تواصل مع الدعم.'; button.disabled = true; }
  }
  document.getElementById('mfaForm').addEventListener('submit', async event => {
    event.preventDefault(); error.textContent = '';
    const code = document.getElementById('code').value.trim();
    if (!factorId || !/^\d{6}$/.test(code)) { error.textContent = 'أدخل رمزًا من 6 أرقام.'; return; }
    button.disabled = true;
    try {
      const { error: verifyError } = await client.auth.mfa.challengeAndVerify({ factorId, code });
      if (verifyError) throw verifyError;
      finish();
    } catch (_) { error.textContent = 'الرمز غير صحيح أو انتهت صلاحيته. حاول مرة أخرى.'; }
    finally { button.disabled = false; }
  });
  document.getElementById('logout').addEventListener('click', async () => {
    if (client) await client.auth.signOut({ scope: 'local' });
    location.replace('login.html');
  });
  init();
})();
