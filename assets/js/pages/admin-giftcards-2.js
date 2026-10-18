async function init() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return; }

  const { data: profile } = await supabaseClient
    .from('profiles').select('role, is_banned').eq('id', session.user.id).single();

  if (!profile || profile.role !== 'admin' || profile.is_banned === true) {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }
  const { data: canManageGiftCards, error: permissionError } = await supabaseClient.rpc('has_admin_permission', { permission_key: 'manage_gift_cards' });
  if (permissionError || canManageGiftCards !== true) {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }

  document.getElementById('adminPage').style.display = 'block';
  document.getElementById('generateBtn').addEventListener('click', generateCard);

  await loadCards();
}

function generateCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = 'RZ-';
  for (let i = 0; i < 8; i++) {
    if (i === 4) code += '-';
    code += chars[crypto.getRandomValues(new Uint8Array(1))[0] % chars.length];
  }
  return code;
}

async function generateCard() {
  const amount = parseFloat(document.getElementById('amountInput').value);
  if (!amount || amount <= 0) {
    alert('أدخل قيمة صحيحة');
    return;
  }

  const code = generateCode();
  const { error } = await supabaseClient.from('gift_cards').insert({ code, amount });

  if (error) {
    alert('حصل خطأ، حاول تاني');
    return;
  }

  document.getElementById('amountInput').value = '';
  await loadCards();
}

async function loadCards() {
  const { data } = await supabaseClient
    .from('gift_cards')
    .select('*, profiles(full_name)')
    .order('created_at', { ascending: false });

  const container = document.getElementById('giftCardsList');
  if (!data || data.length === 0) {
    container.innerHTML = `<div style="color: var(--text-muted); font-size: 13px; text-align: center; padding: 30px 0;">لا توجد كروت بعد</div>`;
    return;
  }

  container.innerHTML = data.map(c => `
    <div class="manage-item">
      <div class="manage-item-info">
        <div class="manage-item-name" style="font-family: var(--font-mono);">
          ${escapeHtml(c.code)}
          ${c.is_redeemed ? '<span class="inactive-badge" style="color: var(--danger); background: rgba(255,77,79,0.15);">مستخدم</span>' : '<span class="inactive-badge" style="color: var(--mm-accent-text); background: rgba(43,237,51,0.15);">متاح</span>'}
        </div>
        <div class="manage-item-sub">
          ${formatSDG(c.amount)} ج.س
          ${c.is_redeemed ? ' — بواسطة: ' + escapeHtml(c.profiles?.full_name || 'مستخدم') : ''}
        </div>
      </div>
    </div>
  `).join('');
}

init();
