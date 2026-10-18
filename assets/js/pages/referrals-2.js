let currentUser = null;

async function init() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return; }
  currentUser = session.user;

  const { data: myProfile } = await supabaseClient
    .from('profiles')
    .select('referral_code, referral_short_code')
    .eq('id', currentUser.id)
    .single();

  if (myProfile) {
    document.getElementById('referralLinkInput').value = `${window.location.origin}/register.html?ref=${encodeURIComponent(myProfile.referral_code || '')}`;
    document.getElementById('referralShortCodeInput').value = myProfile.referral_short_code || '—';
  }

  bindCopyButton('copyRefBtn', 'referralLinkInput', 'نسخ الرابط');
  bindCopyButton('copyShortRefBtn', 'referralShortCodeInput', 'نسخ الكود');

  const { data: discountRow } = await supabaseClient
    .from('settings').select('value').eq('key', 'referral_signup_discount_percent').single();
  const discountPercent = discountRow ? discountRow.value : '5';
  document.getElementById('welcomeDiscountText').textContent = `خصم ترحيبي ${discountPercent}%`;

  const { data: referred } = await supabaseClient
    .from('profiles')
    .select('full_name, referral_rewarded, created_at')
    .eq('referred_by', currentUser.id)
    .order('created_at', { ascending: false });

  const list = referred || [];
  const successCount = list.filter(r => r.referral_rewarded).length;

  document.getElementById('totalCount').textContent = list.length;
  document.getElementById('successCount').textContent = successCount;

  await renderMilestones(successCount);
  renderReferrals(list);
  await loadEarnings();
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>'"]/g, (char) => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', "'":'&#39;', '"':'&quot;' }[char]));
}

function bindCopyButton(buttonId, inputId, idleLabel) {
  document.getElementById(buttonId).addEventListener('click', async () => {
    const input = document.getElementById(inputId);
    const value = input.value.trim();
    if (!value || value === '—') return;
    try {
      await navigator.clipboard.writeText(value);
    } catch (_) {
      input.focus(); input.select(); document.execCommand('copy');
    }
    const btn = document.getElementById(buttonId);
    btn.innerHTML = '<svg class="mm-i" style="margin-left: 6px;" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-check"></use></svg> تم النسخ';
    setTimeout(() => { btn.innerHTML = `<svg class="mm-i" style="margin-left: 6px;" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-copy"></use></svg> ${idleLabel}`; }, 1800);
  });
}

async function renderMilestones(successCount) {
  const { data: milestones } = await supabaseClient
    .from('referral_milestones')
    .select('*')
    .eq('is_active', true)
    .order('threshold');

  const { data: payouts } = await supabaseClient
    .from('referral_milestone_payouts')
    .select('milestone_id')
    .eq('referrer_id', currentUser.id);

  const paidIds = new Set((payouts || []).map(p => p.milestone_id));
  const box = document.getElementById('milestonesBox');

  if (!milestones || milestones.length === 0) {
    box.innerHTML = `<div style="color: var(--text-muted); font-size: 13px;">لا توجد مستويات مكافآت حالياً</div>`;
    return;
  }

  box.innerHTML = milestones.map(m => {
    const achieved = paidIds.has(m.id);
    return `
      <div class="order-card">
        <div class="order-top">
          <div>
            <div class="order-product">${escapeHtml(m.label || 'مستوى')} (${Number(m.threshold) || 0} إحالة)</div>
            <div class="order-date">مكافأة: ${formatSDG(m.bonus)} ج.س</div>
          </div>
          <span class="status-badge ${achieved ? 'status-completed' : 'status-pending_review'}">
            ${achieved ? 'تم التحقيق' : `${Math.min(successCount, Number(m.threshold) || 0)} / ${Number(m.threshold) || 0}`}
          </span>
        </div>
      </div>
    `;
  }).join('');
}

function renderReferrals(list) {
  const container = document.getElementById('referralsList');
  if (list.length === 0) {
    container.innerHTML = `<div style="color: var(--text-muted); font-size: 13px; text-align: center; padding: 20px 0;">لسه ما حدش سجل برابطك</div>`;
    return;
  }

  container.innerHTML = list.map(r => {
    const date = new Date(r.created_at).toLocaleDateString('ar-EG', { year: 'numeric', month: 'short', day: 'numeric' });
    return `
      <div class="mini-list-item">
        <div>
          <div class="name">${escapeHtml(r.full_name || 'مستخدم جديد')}</div>
          <div class="sub">سجل في ${date}</div>
        </div>
        <span class="status-badge ${r.referral_rewarded ? 'status-completed' : 'status-pending_review'}">
          ${r.referral_rewarded ? 'مكتمل' : 'بانتظار أول شراء'}
        </span>
      </div>
    `;
  }).join('');
}

async function loadEarnings() {
  const { data } = await supabaseClient
    .from('notifications')
    .select('*')
    .eq('user_id', currentUser.id)
    .eq('type', 'referral')
    .order('created_at', { ascending: false });

  const container = document.getElementById('earningsList');
  if (!data || data.length === 0) {
    container.innerHTML = `<div style="color: var(--text-muted); font-size: 13px; text-align: center; padding: 20px 0;">لسه مفيش أرباح إحالة</div>`;
    return;
  }

  container.innerHTML = data.map(n => {
    const date = new Date(n.created_at).toLocaleDateString('ar-EG', { year: 'numeric', month: 'short', day: 'numeric' });
    return `
      <div class="mini-list-item">
        <div>
          <div class="name">${escapeHtml(n.title)}</div>
          <div class="sub">${escapeHtml(n.message)}</div>
        </div>
        <div class="sub">${date}</div>
      </div>
    `;
  }).join('');
}

init();
