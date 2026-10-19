// Shared, awaited navigation for password, email OTP, OAuth and TOTP sessions.
(function () {
  'use strict';
  const client = window.supabaseClient;
  const authPage = /\/(login|register|mfa|verify|forgot-password|reset-password)(\.html)?\/?$/;
  function read(key) { try { return sessionStorage.getItem(key); } catch (_) { return null; } }
  function write(key, value) { try { sessionStorage.setItem(key, value); } catch (_) {} }
  function safeReturn(value) {
    try {
      const url = new URL(value || 'index.html', location.origin);
      if (url.origin === location.origin && !url.username && !url.password &&
          /^\/(?:[a-z0-9-]+\.html)?$/.test(url.pathname) && !authPage.test(url.pathname)) {
        return url.pathname + url.search + url.hash;
      }
    } catch (_) {}
    return '/index.html';
  }
  function returnTarget() { return safeReturn(read('meem_mfa_return') || read('redirect_after_login')); }
  async function ensureMfa(target) {
    if (!client?.auth?.mfa) throw new Error('auth_unavailable');
    const { data, error } = await client.auth.mfa.getAuthenticatorAssuranceLevel();
    if (error) throw error;
    if (data?.nextLevel === 'aal2' && data.currentLevel !== 'aal2') {
      write('meem_mfa_return', safeReturn(target));
      location.replace('mfa.html');
      return false;
    }
    return true;
  }
  async function finishSignIn() {
    const target = returnTarget();
    if (!(await ensureMfa(target))) return;
    try {
      sessionStorage.removeItem('meem_mfa_return');
      sessionStorage.removeItem('redirect_after_login');
    } catch (_) {}
    location.replace(target);
  }
  window.MeemAuthFlow = { safeReturn, returnTarget, ensureMfa, finishSignIn, isAuthPage: () => authPage.test(location.pathname) };
  // Auth forms explicitly await the check: a background SIGNED_IN must never
  // overwrite the intended return target with login.html.
  if (!client?.auth?.mfa || authPage.test(location.pathname)) return;
  let checking = false;
  async function check() {
    if (checking) return;
    checking = true;
    try {
      await ensureMfa(location.pathname + location.search + location.hash);
    } catch (_) { /* Database access remains denied until a valid AAL2 session. */ }
    finally { checking = false; }
  }
  client.auth.onAuthStateChange(() => { setTimeout(check, 0); });
  setTimeout(check, 0);
})();
