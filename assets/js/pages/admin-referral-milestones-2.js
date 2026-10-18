let milestones = [];
let editingId = null;

const formModal = document.getElementById('formModal');
const thresholdInput = document.getElementById('thresholdInput');
const bonusInput = document.getElementById('bonusInput');
const labelInput = document.getElementById('labelInput');
const activeInput = document.getElementById('activeInput');
const formError = document.getElementById('formError');

async function init() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return; }

  const { data: profile } = await supabaseClient
    .from('profiles').select('role, is_banned').eq('id', session.user.id).single();

  if (!profile || profile.role !== 'admin' || profile.is_banned === true) {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }
  const { data: canManageSettings, error: permissionError } = await supabaseClient.rpc('has_admin_permission', { permission_key: 'manage_settings' });
  if (permissionError || canManageSettings !== true) {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }

  document.getElementById('adminPage').style.display = 'block';
  document.getElementById('addNewBtn').addEventListener('click', () => openForm(null));
  document.getElementById('formCancelBtn').addEventListener('click', closeForm);
  document.getElementById('formSaveBtn').addEventListener('click', saveMilestone);

  await loadMilestones();
}

async function loadMilestones() {
  const { data } = await supabaseClient.from('referral_milestones').select('*').order('threshold');
  milestones = data || [];
  render();
}

function render() {
  const container = document.getElementById('milestonesList');
  if (milestones.length === 0) {
    container.innerHTML = `<div style="color: var(--text-muted); font-size: 13px; text-align: center; padding: 30px 0;">لا توجد مستويات بعد</div>`;
    return;
  }

  container.innerHTML = milestones.map(m => `
    <div class="manage-item">
      <div class="manage-item-info">
        <div class="manage-item-name">
          ${m.label || 'مستوى'} — ${m.threshold} إحالة
          ${!m.is_active ? '<span class="inactive-badge">معطّل</span>' : ''}
        </div>
        <div class="manage-item-sub">مكافأة: ${formatSDG(m.bonus)} ج.س</div>
      </div>
      <div class="manage-item-actions">
        <button class="icon-action-btn" data-action="edit" data-id="${m.id}"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-pen"></use></svg></button>
        <button class="icon-action-btn" data-action="delete" data-id="${m.id}"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-trash-2"></use></svg></button>
      </div>
    </div>
  `).join('');

  container.querySelectorAll('[data-action="edit"]').forEach(btn => {
    btn.addEventListener('click', () => openForm(btn.dataset.id));
  });
  container.querySelectorAll('[data-action="delete"]').forEach(btn => {
    btn.addEventListener('click', () => deleteMilestone(btn.dataset.id));
  });
}

function openForm(id) {
  editingId = id;
  formError.textContent = '';

  if (id) {
    const m = milestones.find(x => x.id === id);
    document.getElementById('formModalTitle').textContent = 'تعديل المستوى';
    thresholdInput.value = m.threshold;
    bonusInput.value = m.bonus;
    labelInput.value = m.label || '';
    activeInput.value = String(m.is_active);
  } else {
    document.getElementById('formModalTitle').textContent = 'مستوى جديد';
    thresholdInput.value = '';
    bonusInput.value = '';
    labelInput.value = '';
    activeInput.value = 'true';
  }

  formModal.classList.add('show');
}

function closeForm() {
  formModal.classList.remove('show');
  editingId = null;
}

async function saveMilestone() {
  const threshold = parseInt(thresholdInput.value);
  const bonus = parseFloat(bonusInput.value);

  if (!threshold || threshold <= 0) { formError.textContent = 'أدخل عدد إحالات صحيح'; return; }
  if (!bonus || bonus <= 0) { formError.textContent = 'أدخل قيمة مكافأة صحيحة'; return; }

  const payload = {
    threshold,
    bonus,
    label: labelInput.value.trim() || null,
    is_active: activeInput.value === 'true'
  };

  const { error } = editingId
    ? await supabaseClient.from('referral_milestones').update(payload).eq('id', editingId)
    : await supabaseClient.from('referral_milestones').insert(payload);

  if (error) {
    formError.textContent = 'حصل خطأ، حاول تاني';
    return;
  }

  closeForm();
  await loadMilestones();
}

async function deleteMilestone(id) {
  if (!confirm('متأكد عايز تحذف المستوى ده؟')) return;
  const { error } = await supabaseClient.from('referral_milestones').delete().eq('id', id);
  if (error) { alert('تعذّر حذف المستوى: ' + getFriendlyError(error)); return; }
  await loadMilestones();
}

init();
