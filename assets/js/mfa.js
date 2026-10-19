(function () {
  'use strict';
  const client = window.supabaseClient;
  const error = document.getElementById('error');
  const button = document.getElementById('verify');
  let factorId = null;
  async function finish() { await window.MeemAuthFlow.finishSignIn(); }
  async function init() {
    try {
      if (!client?.auth?.mfa) throw new Error('unavailable');
      const { data: session } = await client.auth.getSession();
      if (!session?.session) { location.replace('login.html'); return; }
      const { data: aal, error: aalError } = await client.auth.mfa.getAuthenticatorAssuranceLevel();
      if (aalError) throw aalError;
      if (aal?.currentLevel === 'aal2' || aal?.nextLevel !== 'aal2') { await finish(); return; }
      const { data, error: factorsError } = await client.auth.mfa.listFactors();
      if (factorsError) throw factorsError;
      factorId = (data?.totp || []).find(f => f.status === 'verified')?.id || null;
      if (!factorId) throw new Error('factor_unavailable');
    } catch (_) { error.textContent = 'تعذر تجهيز التحقق بخطوتين. أعد المحاولة أو تواصل مع الدعم.'; button.disabled = true; }
  }
  document.getElementById('mfaForm').addEventListener('submit', async event => {
    event.preventDefault(); error.textContent = '';
    const code = document.getElementById('code').value.trim();
    if (button.disabled) return;
    if (!factorId || !/^\d{6}$/.test(code)) { error.textContent = 'أدخل رمزًا من 6 أرقام.'; return; }
    button.disabled = true;
    try {
      const { error: verifyError } = await client.auth.mfa.challengeAndVerify({ factorId, code });
      if (verifyError) throw verifyError;
      const { data: assurance, error: assuranceError } = await client.auth.mfa.getAuthenticatorAssuranceLevel();
      if (assuranceError || assurance?.currentLevel !== 'aal2') throw new Error('session_not_upgraded');
      await finish();
    } catch (_) { error.textContent = 'الرمز غير صحيح أو انتهت صلاحيته. حاول مرة أخرى.'; }
    finally { button.disabled = false; }
  });
  document.getElementById('logout').addEventListener('click', async () => {
    if (client) await client.auth.signOut({ scope: 'local' });
    location.replace('login.html');
  });
  init();
})();
