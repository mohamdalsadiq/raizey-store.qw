/* Never navigate to a stored URL. Resolve only this project's private bucket. */
(function (root) {
  'use strict';
  function objectPath(value) {
    if (typeof value !== 'string' || !value.trim()) return null;
    let path = value.trim();
    if (/^https:\/\//i.test(path)) {
      try {
        const url = new URL(path), project = new URL(root.SUPABASE_URL);
        if (url.origin !== project.origin || url.username || url.password) return null;
        const match = url.pathname.match(/^\/storage\/v1\/object\/(?:sign|public|authenticated)\/receipts\/(.+)$/);
        if (!match) return null;
        path = decodeURIComponent(match[1]);
      } catch { return null; }
    } else path = path.replace(/^\/?receipts\//, '');
    if (path.length > 512 || !/^[0-9a-f-]{36}\/(?:[A-Za-z0-9_-][A-Za-z0-9._-]*\/)*[A-Za-z0-9_-][A-Za-z0-9._-]*\.(?:jpg|jpeg|png|webp)$/i.test(path)) return null;
    if (path.split('/').some(part => part === '.' || part === '..')) return null;
    return path;
  }
  async function signedUrl(reference) {
    const path = objectPath(reference);
    if (!path) throw new Error('invalid_receipt_reference');
    const { data, error } = await root.supabaseClient.storage.from('receipts').createSignedUrl(path, 300);
    if (error || !data?.signedUrl) throw new Error('receipt_access_denied');
    const url = new URL(data.signedUrl);
    if (url.origin !== new URL(root.SUPABASE_URL).origin || objectPath(data.signedUrl) !== path) throw new Error('invalid_receipt_reference');
    return url.href;
  }
  document.addEventListener('click', async event => {
    const link = event.target.closest?.('[data-receipt-reference]');
    if (!link) return;
    event.preventDefault();
    if (link.dataset.busy) return;
    link.dataset.busy = 'true';
    const label = link.textContent;
    // Open while the user gesture is active; clear opener before any navigation.
    const tab = root.open('about:blank', '_blank');
    if (tab) tab.opener = null;
    link.textContent = 'جارِ فتح الإيصال...';
    try {
      const url = await signedUrl(link.dataset.receiptReference);
      if (tab) tab.location.replace(url); else root.location.assign(url);
      link.textContent = label;
    } catch {
      tab?.close();
      link.textContent = 'تعذّر فتح الإيصال؛ اضغط لإعادة المحاولة';
    } finally { delete link.dataset.busy; }
  });
  root.MeemReceiptLinks = { objectPath, signedUrl };
})(window);
