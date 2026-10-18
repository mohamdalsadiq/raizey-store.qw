// Enrolled MFA is enforced in PostgreSQL too. This guard supplies the challenge UI.
(function () {
  'use strict';
  const client = window.supabaseClient;
  if (!client?.auth?.mfa || /\/(mfa|forgot-password|reset-password|verify)\.html$/.test(location.pathname)) return;
  let checking = false;
  async function check() {
    if (checking) return;
    checking = true;
    try {
      const { data, error } = await client.auth.mfa.getAuthenticatorAssuranceLevel();
      if (!error && data?.nextLevel === 'aal2' && data.currentLevel !== 'aal2') {
        const target = location.pathname + location.search;
        sessionStorage.setItem('meem_mfa_return', target);
        location.replace('mfa.html');
      }
    } catch (_) { /* Database access remains denied until a valid AAL2 session. */ }
    finally { checking = false; }
  }
  client.auth.onAuthStateChange(() => { setTimeout(check, 0); });
  setTimeout(check, 0);
})();
