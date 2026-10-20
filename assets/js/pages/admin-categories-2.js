let categories = [];
let sections = [];
let editingId = null;

const formModal = document.getElementById('formModal');
const sectionInput = document.getElementById('sectionInput');
const nameInput = document.getElementById('nameInput');
const descriptionInput = document.getElementById('descriptionInput');
const imageFileInput = document.getElementById('imageFileInput');
const imageUrlInput = document.getElementById('imageUrlInput');
const imageUploadStatus = document.getElementById('imageUploadStatus');
const orderInput = document.getElementById('orderInput');
const activeInput = document.getElementById('activeInput');
const formError = document.getElementById('formError');
const categoriesNotice = document.getElementById('categoriesNotice');

function showCategoriesNotice(message, type = 'error') {
  categoriesNotice.textContent = message || '';
  categoriesNotice.className = `admin-inline-notice ${type}`;
  categoriesNotice.hidden = !message;
}

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
  document.getElementById('formSaveBtn').addEventListener('click', saveCategory);

  await loadSections();
  await loadCategories();
}

async function loadSections() {
  const { data, error } = await supabaseClient
    .from('store_sections').select('id,name,is_active,display_order').order('display_order').order('name');
  if (error) {
    showCategoriesNotice('تعذر تحميل الأقسام. أضف قسمًا أولًا من صفحة إدارة الأقسام.', 'error');
    return;
  }
  sections = data || [];
  sectionInput.innerHTML = '<option value="">اختر القسم أولًا</option>' + sections.map(s => `<option value="${s.id}">${escapeHtml(s.name)}${s.is_active ? '' : ' — مؤرشف'}</option>`).join('');
}

async function loadCategories() {
    const { data, error } = await supabaseClient
      .from('categories').select('*').not('section_id', 'is', null).order('display_order');
    if (error) {
      formError.textContent = 'تعذر تحميل التصنيفات. حدّث الصفحة وحاول مرة أخرى.';
      devLog('[MEEM] load categories error:', { code: error.code, message: error.message });
      return;
    }
    categories = data || [];
    render();
}

function catSprite(key) {
  return window.MeemCategoryIcons.createIcon(key);
}

function render() {
  const container = document.getElementById('categoriesList');
  if (categories.length === 0) {
    container.innerHTML = `<div style="color: var(--text-muted); font-size: 13px; text-align: center; padding: 30px 0;">لا توجد تصنيفات بعد</div>`;
    return;
  }

  container.innerHTML = categories.map(c => {
    const imgHtml = c.image_url
      ? `<img src="${escapeHtml(c.image_url)}" class="category-thumb" alt="${escapeHtml(c.name)}">`
      : `<div class="category-thumb" data-caticon="${c.id}" style="background: var(--bg-card); display: flex; align-items: center; justify-content: center; color: var(--mm-accent-text);"></div>`;

    return `
      <div class="manage-item">
        <div class="manage-item-info">
          ${imgHtml}
          <div class="category-meta-text">
            <div class="manage-item-name">
              ${escapeHtml(c.name)}
              ${!c.is_active ? '<span class="inactive-badge">مخفي</span>' : ''}
            </div>
            <div class="manage-item-sub">القسم: ${escapeHtml(sections.find(s => s.id === c.section_id)?.name || 'بدون قسم')} — ترتيب: ${c.display_order} — عمولة: ${c.commission_percent}%</div>
          </div>
        </div>
        <div class="manage-item-actions">
          <button data-action="edit" data-id="${c.id}" class="admin-action-btn" title="تعديل">
            <svg class="mm-i" style="color: var(--text-muted);" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-pen"></use></svg>
          </button>
          <button data-action="delete" data-id="${c.id}" class="admin-action-btn" title="حذف">
            <svg class="mm-i" style="color: var(--danger);" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-trash-2"></use></svg>
          </button>
        </div>
      </div>
    `;
  }).join('');

  // resolved icon for rows without a cover image (auto/preset/custom)
  if (window.MeemCategoryIcons) {
    categories.forEach((c) => {
      const slot = container.querySelector('[data-caticon="' + c.id + '"]');
      if (!slot) return;
      const spec = window.MeemCategoryIcons.resolve(c);
      if (spec.mode === 'custom' && spec.image) {
        const img = document.createElement('img');
        img.src = spec.image; img.alt = ''; img.width = 22; img.height = 22;
        img.addEventListener('error', () => { slot.replaceChildren(catSprite(spec.key)); }, { once: true });
        slot.replaceChildren(img);
      } else {
        slot.replaceChildren(catSprite(window.MeemCategoryIcons.isValidKey(spec.key) ? spec.key : 'layout-grid'));
      }
    });
  }
  container.querySelectorAll('[data-action="edit"]').forEach(btn => {
    btn.addEventListener('click', () => openForm(btn.dataset.id));
  });
  container.querySelectorAll('[data-action="delete"]').forEach(btn => {
    btn.addEventListener('click', () => deleteCategory(btn.dataset.id));
  });
}

let categoryIconPicker = null;
function mountCategoryIconPicker(cat) {
  if (!window.MeemIconPicker) return;
  categoryIconPicker = window.MeemIconPicker.mount(document.getElementById('categoryIconPicker'), {
    row: cat || {},
    nameProvider: () => nameInput.value
  });
}
function openForm(id) {
  editingId = id;
  formError.textContent = '';
  imageFileInput.value = '';
  imageUploadStatus.textContent = '';

  if (id) {
    const cat = categories.find(c => c.id === id);
    document.getElementById('formModalTitle').textContent = 'تعديل التصنيف';
    sectionInput.value = cat.section_id || '';
    nameInput.value = cat.name;
    descriptionInput.value = cat.description || '';
    imageUrlInput.value = cat.image_url || '';
    if (cat.image_url) {
      imageUploadStatus.textContent = 'توجد صورة مرفوعة بالفعل. اختر ملفاً جديداً لاستبدالها.';
    }
    orderInput.value = cat.display_order;
    document.getElementById('commissionInput').value = cat.commission_percent ?? 3;
    activeInput.value = String(cat.is_active);
    mountCategoryIconPicker(cat);
  } else {
    document.getElementById('formModalTitle').textContent = 'تصنيف جديد';
    sectionInput.value = '';
    nameInput.value = '';
    descriptionInput.value = '';
    imageUrlInput.value = '';
    orderInput.value = categories.length;
    document.getElementById('commissionInput').value = 3;
    activeInput.value = 'true';
    mountCategoryIconPicker({});
  }

  formModal.classList.add('show');
}

function closeForm() {
  formModal.classList.remove('show');
  editingId = null;
}

async function uploadCategoryImageFile(file) {
  const allowedTypes = ['image/jpeg', 'image/png', 'image/webp'];
  if (!allowedTypes.includes(file.type)) {
    throw new Error('invalid_image_type');
  }
  if (file.size > 5 * 1024 * 1024) {
    throw new Error('image_too_large');
  }
  imageUploadStatus.textContent = 'جاري رفع الصورة...';
  const fileExt = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg';
  const fileName = `categories/${Date.now()}.${fileExt}`;

  const { data, error } = await supabaseClient.storage
    .from('product-images')
    .upload(fileName, file);

  if (error) {
    throw error;
  }

  const { data: publicUrlData } = supabaseClient.storage
    .from('product-images')
    .getPublicUrl(fileName);

  return publicUrlData.publicUrl;
}

async function saveCategory() {
  const sectionId = sectionInput.value;
  const name = nameInput.value.trim();
  const description = descriptionInput.value.trim();
  const order = parseInt(orderInput.value) || 0;
  const isActive = activeInput.value === 'true';

  if (!sectionId) {
    formError.textContent = 'اختر القسم الذي سيظهر تحته التصنيف.';
    return;
  }
  if (!name) {
    formError.textContent = 'أدخل اسم التصنيف';
    return;
  }

  document.getElementById('formSaveBtn').disabled = true;
  document.getElementById('formSaveBtn').textContent = 'جاري الحفظ...';

  try {
    let finalImageUrl = imageUrlInput.value;

    if (imageFileInput.files.length > 0) {
      finalImageUrl = await uploadCategoryImageFile(imageFileInput.files[0]);
    }

    const payload = {
      section_id: sectionId,
      name,
      description,
      image_url: finalImageUrl,
      display_order: order,
      commission_percent: parseFloat(document.getElementById('commissionInput').value) || 3,
      is_active: isActive
    };

    let categoryId = editingId;
    if (editingId) {
      const { error } = await supabaseClient.from('categories').update(payload).eq('id', editingId);
      if (error) {
        const code = error.code || '';
        formError.textContent = code === '42501'
          ? 'ليس لديك صلاحية إدارة التصنيفات. تأكد من سياسة categories_admin في Supabase.'
          : 'تعذر حفظ التصنيف. تحقق من البيانات ثم حاول مرة أخرى.';
        devLog('[MEEM] save category error:', { code, message: error.message });
        return;
      }
    } else {
      const { data: inserted, error } = await supabaseClient.from('categories').insert(payload).select('id').single();
      if (error) {
        formError.textContent = 'تعذر حفظ التصنيف. تحقق من البيانات ثم حاول مرة أخرى.';
        devLog('[MEEM] save category error:', { code: error.code, message: error.message });
        return;
      }
      categoryId = inserted.id;
    }

    // icon columns are optional (the picker still works once the migration lands)
    if (categoryIconPicker && categoryId) {
      try {
        const icon = await categoryIconPicker.resolve();
        const { error: iconErr } = await supabaseClient.rpc('admin_set_category_icon', {
          p_id: categoryId, p_mode: icon.icon_mode, p_key: icon.icon_key, p_image: icon.icon_image_url
        });
        if (iconErr && iconErr.message && iconErr.message.indexOf('does not exist') === -1) {
          showCategoriesNotice('تم حفظ التصنيف لكن تعذر حفظ الأيقونة: ' + iconErr.message, 'error');
        }
      } catch (iconErr) {
        showCategoriesNotice('تم حفظ التصنيف لكن تعذر حفظ الأيقونة: ' + (iconErr.message || iconErr), 'error');
      }
    }

    closeForm();
    await loadCategories();
  } catch (err) {
    console.error(err);
    formError.textContent = err?.message === 'invalid_image_type'
      ? 'اختر صورة JPG أو PNG أو WEBP فقط.'
      : err?.message === 'image_too_large'
        ? 'حجم الصورة أكبر من 5MB.'
        : 'تعذر رفع الصورة. حاول مرة أخرى.';
  } finally {
    document.getElementById('formSaveBtn').disabled = false;
    document.getElementById('formSaveBtn').textContent = 'حفظ';
    document.getElementById('formSaveBtn').style.background = 'var(--primary)';
  }
}

async function deleteCategory(id) {
  if (!confirm('هل تريد حذف هذا التصنيف؟ لا يمكن حذفه إذا كانت هناك منتجات أو تصنيفات فرعية مرتبطة به.')) return;

  showCategoriesNotice('جاري حذف التصنيف...', '');
  const { data: deletedRows, error } = await supabaseClient
    .from('categories')
    .delete({ count: 'exact' })
    .eq('id', id)
    .select('id');

  if (error) {
    const code = error.code || '';
    const message = code === '23503'
      ? 'لا يمكن حذف التصنيف لأنه مرتبط بمنتجات أو تصنيفات فرعية. انقل العناصر أولاً ثم حاول مرة أخرى.'
      : code === '42501'
        ? 'ليست لديك صلاحية حذف التصنيفات. اطلب من المدير تفعيل صلاحية إدارة المنتجات.'
        : 'تعذر حذف التصنيف. حاول مرة أخرى.';
    showCategoriesNotice(message, 'error');
    devLog('[MEEM] delete category error:', { code, message: error.message });
    return;
  }

  // RLS قد يمنع الحذف بإرجاع صفوف فارغة دون خطأ صريح.
  if (!Array.isArray(deletedRows) || deletedRows.length !== 1) {
    const { data: canManage } = await supabaseClient.rpc('has_admin_permission', {
      permission_key: 'manage_products'
    });
    const message = canManage === false
      ? 'لم يتم الحذف لأن حسابك لا يملك صلاحية إدارة المنتجات.'
      : 'لم يتم حذف التصنيف. قد يكون محميًا بعناصر مرتبطة أو لم يعد موجودًا.';
    showCategoriesNotice(message, 'error');
    devLog('[MEEM] delete category affected no rows:', { id, canManage });
    await loadCategories();
    return;
  }

  showCategoriesNotice('تم حذف التصنيف بنجاح.', 'success');
  await loadCategories();
}

init();
