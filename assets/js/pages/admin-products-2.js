let products = [];
let categories = [];
let editingId = null;

const formModal = document.getElementById('formModal');
const categoryInput = document.getElementById('categoryInput');
const nameInput = document.getElementById('nameInput');
const descInput = document.getElementById('descInput');
const deliveryBadgeInput = document.getElementById('deliveryBadgeInput');
const instructionsInput = document.getElementById('instructionsInput');
const imageInput = document.getElementById('imageInput');
const priceInput = document.getElementById('priceInput');
const orderInput = document.getElementById('orderInput');
const activeInput = document.getElementById('activeInput');
const formError = document.getElementById('formError');
const fieldsBuilder = document.getElementById('fieldsBuilder');

const hasOptionsToggle = document.getElementById('hasOptionsToggle');
const optionsContainer = document.getElementById('optionsContainer');
const optionsBuilder = document.getElementById('optionsBuilder');
const addOptionBtn = document.getElementById('addOptionBtn');

async function init() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return; }

  const { data: profile } = await supabaseClient
    .from('profiles').select('role, is_banned').eq('id', session.user.id).single();

  if (!profile || profile.role !== 'admin' || profile.is_banned === true) {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }

  const { data: canManageProducts } = await supabaseClient.rpc('has_admin_permission', {
    permission_key: 'manage_products'
  });
  if (canManageProducts !== true) {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }

  document.getElementById('adminPage').style.display = 'block';
  document.getElementById('addNewBtn').addEventListener('click', () => openForm(null));
  document.getElementById('formCancelBtn').addEventListener('click', closeForm);
  document.getElementById('formSaveBtn').addEventListener('click', saveProduct);
  document.getElementById('addFieldBtn').addEventListener('click', () => addFieldRow('', '', ''));

  hasOptionsToggle.addEventListener('change', () => toggleOptionsSection(hasOptionsToggle.checked));
  addOptionBtn.addEventListener('click', () => addOptionRow('', '', ''));

  const fileBox = document.getElementById('fileUploadBox');
  const fileInput = document.getElementById('imageFileInput');
  fileBox.addEventListener('click', () => fileInput.click());
  fileInput.addEventListener('change', async () => {
    if (fileInput.files.length === 0) return;
    const file = fileInput.files[0];
    const allowedTypes = ['image/jpeg', 'image/png', 'image/webp'];
    if (!allowedTypes.includes(file.type)) {
      fileBox.textContent = 'اختر صورة JPG أو PNG أو WEBP فقط';
      fileInput.value = '';
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      fileBox.textContent = 'حجم الصورة أكبر من 5MB';
      fileInput.value = '';
      return;
    }
    fileBox.textContent = 'جارِ الرفع...';

    const fileExt = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg';
    const filePath = `${Date.now()}-${Math.random().toString(36).slice(2)}.${fileExt}`;

    const { error } = await supabaseClient.storage.from('product-images').upload(filePath, file);
    if (error) {
      fileBox.textContent = 'فشل الرفع، اضغط للمحاولة تاني';
      return;
    }

    const { data: urlData } = supabaseClient.storage.from('product-images').getPublicUrl(filePath);
    document.getElementById('imageInput').value = urlData.publicUrl;
    fileBox.textContent = `${file.name}`;
    fileBox.classList.add('has-file');
  });

  await loadCategories();
  await loadProducts();
}

function toggleOptionsSection(show) {
  optionsContainer.style.display = show ? 'block' : 'none';
  // التحقق: لا نضيف صفوفاً فارغة إلا إذا لم يكن هناك خيارات حالية
  if (show && optionsBuilder.children.length === 0) {
    addOptionRow('', '', '');
    addOptionRow('', '', '');
  }
}

function addOptionRow(label = '', price = '', id = '') {
  const row = document.createElement('div');
  row.className = 'option-row';
  row.style.cssText = 'display: flex; gap: 8px; align-items: center; margin-bottom: 10px;';

  const cleanLabel = escapeAttribute(label || '');
  const safeId = id || 'opt_' + Date.now().toString(36) + '_' + Math.random().toString(36).substring(2, 6);

  row.innerHTML = `
    <input type="hidden" class="opt-id" value="${escapeAttribute(safeId)}">
    <input type="text" placeholder="اسم الخيار (مثلاً: حساب موثق)" class="opt-label" value="${cleanLabel}" style="flex: 2; padding: 10px; border-radius: 8px; border: 1px solid var(--border); background: var(--bg); color: var(--ink); font-family: var(--mm-font-display); font-size: 13px;" required>
    <input type="number" step="0.01" placeholder="السعر ($)" class="opt-price" value="${escapeAttribute(price)}" style="flex: 1; padding: 10px; border-radius: 8px; border: 1px solid var(--border); background: var(--bg); color: var(--ink); font-family: var(--mm-font-display); font-size: 13px;" required>
    <button type="button" style="background: var(--danger, var(--mm-danger-fill)); color: white; border: none; border-radius: 8px; padding: 10px 12px; cursor: pointer; font-size: 13px;"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-trash-2"></use></svg></button>
  `;
  row.querySelector('button').addEventListener('click', () => row.remove());
  optionsBuilder.appendChild(row);
}

function collectOptions() {
  if (!hasOptionsToggle.checked) return [];
  const rows = optionsBuilder.querySelectorAll('.option-row');
  const options = [];

  rows.forEach((row) => {
    const id = row.querySelector('.opt-id').value;
    const label = row.querySelector('.opt-label').value.trim();
    const price = parseFloat(row.querySelector('.opt-price').value) || 0;
    if (label) {
      options.push({
        id: id,
        label: label,
        price_usd: price
      });
    }
  });

  return options;
}

async function loadCategories() {
  const { data } = await supabaseClient
    .from('categories')
    .select('id,name,section_id,is_active')
    .eq('is_active', true)
    .not('section_id', 'is', null)
    .order('display_order');
  categories = data || [];
  categoryInput.innerHTML = categories.length
    ? categories.map(c => `<option value="${c.id}">${escapeHtml(c.name)}</option>`).join('')
    : '<option value="">أضف قسمًا وتصنيفًا فعّالًا أولًا</option>';
}

async function loadProducts() {
  const { data } = await supabaseClient
    .from('products').select('*, categories(name,section_id)').order('display_order');
  products = data || [];
  render();
}

function render() {
  const container = document.getElementById('productsList');
  if (products.length === 0) {
    container.innerHTML = `<div style="color: var(--text-muted); font-size: 13px; text-align: center; padding: 30px 0;">لا توجد منتجات بعد</div>`;
    return;
  }

  container.innerHTML = products.map(p => `
    <div class="manage-item">
      <div class="manage-item-thumb">
        ${p.image_url ? `<img src="${escapeHtml(p.image_url)}" alt="" loading="lazy">` : 'لا صورة'}
      </div>
      <div class="manage-item-info">
        <div class="manage-item-name">
          ${escapeHtml(p.name)}
          ${!p.is_active ? '<span class="inactive-badge">مخفي</span>' : ''}
          ${Array.isArray(p.options) && p.options.length > 0 ? '<span class="inactive-badge" style="background: rgba(255, 212, 0,0.12); color: var(--mm-accent-text);">خيارات متعددة</span>' : ''}
        </div>
        <div class="manage-item-sub">${escapeHtml(p.categories?.name || 'بدون تصنيف')} — $${parseFloat(p.price_usd).toFixed(2)} — ${Array.isArray(p.options) && p.options.length ? `${p.options.length} اختيارات` : 'سعر أساسي'}</div>
      </div>
      <div class="manage-item-actions">
        <button class="icon-action-btn" data-action="edit" data-id="${p.id}"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-pen"></use></svg></button>
        <button class="icon-action-btn" data-action="delete" data-id="${p.id}"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-trash-2"></use></svg></button>
      </div>
    </div>
  `).join('');

  container.querySelectorAll('[data-action="edit"]').forEach(btn => {
    btn.addEventListener('click', () => openForm(btn.dataset.id));
  });
  container.querySelectorAll('[data-action="delete"]').forEach(btn => {
    btn.addEventListener('click', () => deleteProduct(btn.dataset.id));
  });
}

function addFieldRow(key, label, placeholder = '') {
  const row = document.createElement('div');
  row.className = 'field-row';
  row.style.display = 'flex';
  row.style.gap = '10px';
  row.style.marginBottom = '12px';
  row.style.alignItems = 'center';

  const safeKey = key || 'field_' + Date.now() + Math.random().toString(36).substring(2, 5);

  row.innerHTML = `
    <input type="text" placeholder="العنوان فوق (مثال: ايدي اللاعب)" class="field-label" value="${escapeAttribute(label)}" style="flex: 1; padding: 10px; border-radius: 8px; border: 1px solid var(--border); background: var(--bg); color: var(--ink); font-family: var(--mm-font-display); font-size: 13px;">
    <input type="text" placeholder="الداخل الصندوق (مثال: ID)" class="field-placeholder" value="${escapeAttribute(placeholder)}" style="flex: 1; padding: 10px; border-radius: 8px; border: 1px solid var(--border); background: var(--bg); color: var(--ink); font-family: var(--mm-font-display); font-size: 13px;">
    <input type="hidden" class="field-key" value="${escapeAttribute(safeKey)}">
    <button type="button" style="background: var(--mm-danger-fill); color: var(--white); border: none; border-radius: 8px; padding: 10px 14px; cursor: pointer; font-weight: bold; font-size: 14px; transition: 0.2s;"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-x"></use></svg></button>
  `;
  row.querySelector('button').addEventListener('click', () => row.remove());
  fieldsBuilder.appendChild(row);
}

function openForm(id) {
  editingId = id;
  formError.textContent = '';
  fieldsBuilder.innerHTML = '';
  optionsBuilder.innerHTML = ''; // تنظيف الخيارات أولاً

  const fileBox = document.getElementById('fileUploadBox');

  if (id) {
    const p = products.find(x => x.id === id);
    document.getElementById('formModalTitle').textContent = 'تعديل المنتج';
    categoryInput.value = p.category_id || '';
    nameInput.value = p.name;
    descInput.value = p.description || '';
    deliveryBadgeInput.value = p.delivery_badge_text || '';
    instructionsInput.value = p.instructions || '';
    document.getElementById('imageInput').value = p.image_url || '';
    fileBox.textContent = p.image_url ? 'يوجد صورة مرفوعة (اضغط للتغيير)' : 'اضغط لرفع صورة';
    fileBox.classList.toggle('has-file', !!p.image_url);
    priceInput.value = p.price_usd;
    orderInput.value = p.display_order;
    activeInput.value = String(p.is_active);

    // اقرأ العلم المحفوظ نفسه؛ لا تستنتجه من وجود بيانات قديمة في options.
    // هذا يمنع عودة checkbox مفعّلاً بعد أن أغلقه المشرف وحفظ المنتج.
    const hasSavedOptions = p.has_options === true;
    hasOptionsToggle.checked = hasSavedOptions;
    optionsContainer.style.display = hasSavedOptions ? 'block' : 'none';
    if (hasSavedOptions && Array.isArray(p.options)) {
      p.options.forEach(opt => addOptionRow(opt.label, opt.price_usd ?? opt.price ?? '', opt.id));
    }

    (p.required_fields || []).forEach(f => addFieldRow(f.key, f.label, f.placeholder || ''));
  } else {
    document.getElementById('formModalTitle').textContent = 'منتج جديد';
    nameInput.value = '';
    descInput.value = '';
    deliveryBadgeInput.value = '';
    instructionsInput.value = '';
    document.getElementById('imageInput').value = '';
    fileBox.textContent = 'اضغط لرفع صورة';
    fileBox.classList.remove('has-file');
    priceInput.value = '';
    orderInput.value = products.length;
    activeInput.value = 'true';

    hasOptionsToggle.checked = false;
    optionsContainer.style.display = 'none';
  }

  formModal.classList.add('show');
}

function closeForm() {
  formModal.classList.remove('show');
  editingId = null;
}

function collectFields() {
  const rows = fieldsBuilder.querySelectorAll('.field-row');
  const fields = [];
  for (const row of rows) {
    const key = row.querySelector('.field-key').value.trim();
    const label = row.querySelector('.field-label').value.trim();
    const placeholder = row.querySelector('.field-placeholder').value.trim();
    if (label) {
      fields.push({ key, label, placeholder });
    }
  }
  return fields;
}

async function saveProduct() {
  const name = nameInput.value.trim();
  const price = parseFloat(priceInput.value);
  const categoryId = categoryInput.value;

  if (!name) { formError.textContent = 'أدخل اسم المنتج'; return; }
  if (!price || price <= 0) { formError.textContent = 'أدخل سعرًا صحيحًا للمنتج'; return; }
  if (!categoryId) { formError.textContent = 'اختر تصنيفًا'; return; }

  const options = collectOptions();
  if (hasOptionsToggle.checked && options.length < 2) {
    formError.textContent = 'عند تفعيل الخيارات الفرعية، يجب إضافة خيارين على الأقل.';
    return;
  }

  const payload = {
    name,
    description: descInput.value.trim() || null,
    delivery_badge_text: deliveryBadgeInput.value.trim() || null,
    instructions: instructionsInput.value.trim() || null,
    image_url: imageInput.value.trim() || null,
    price_usd: price,
    category_id: categoryId,
    display_order: parseInt(orderInput.value, 10) || 0,
    is_active: activeInput.value === 'true',
    required_fields: collectFields(),
    options,
    has_options: hasOptionsToggle.checked
  };

  const { error } = editingId
    ? await supabaseClient.from('products').update(payload).eq('id', editingId)
    : await supabaseClient.from('products').insert(payload);

  if (error) {
    const code = error.code || '';
    const message = code === '42501'
      ? 'ليس لديك صلاحية حفظ المنتجات. طبّق سياسة products_admin_all في Supabase.'
      : code === '23503'
        ? 'التصنيف المختار غير موجود، حدّث الصفحة واختر تصنيفًا صحيحًا.'
        : 'تعذر حفظ المنتج. تحقق من الحقول المطلوبة ثم حاول مرة أخرى.';
    formError.textContent = message;
    devLog('[MEEM] save product error:', { code, message: error.message });
    return;
  }

  closeForm();
  await loadProducts();
}

async function deleteProduct(id) {
  if (!confirm('متأكد عايز تحذف المنتج ده؟')) return;
  const { error } = await supabaseClient.from('products').delete().eq('id', id);
  if (error) { alert('تعذّر حذف المنتج: ' + getFriendlyError(error)); return; }
  await loadProducts();
}

init();
