let sections = [];
    let editingId = null;
    const formModal = document.getElementById('formModal');
    const nameInput = document.getElementById('nameInput');
    const orderInput = document.getElementById('orderInput');
    const activeInput = document.getElementById('activeInput');
    const formError = document.getElementById('formError');
    const notice = document.getElementById('sectionsNotice');

    function showNotice(message, type = 'error') {
      notice.textContent = message || '';
      notice.className = `admin-inline-notice ${type}`;
      notice.hidden = !message;
    }
    function errorText(error) {
      const code = error?.code || '';
      if (code === '23505') return 'يوجد قسم بنفس الاسم. اكتب اسمًا مختلفًا.';
      if (code === '23503') return 'لا يمكن حذف القسم لأنه يحتوي على تصنيفات. انقل التصنيفات أولًا.';
      if (code === '42501') return 'ليست لديك صلاحية إدارة الأقسام.';
      return 'تعذر تنفيذ العملية. راجع البيانات وحاول مرة أخرى.';
    }
    async function hasAccess() {
      const { data: { session } } = await supabaseClient.auth.getSession();
      if (!session) { window.location.href = 'login.html'; return false; }
      const { data: profile } = await supabaseClient.from('profiles').select('role,is_banned').eq('id', session.user.id).single();
      if (!profile || profile.role !== 'admin' || profile.is_banned === true) return false;
      const { data: allowed, error } = await supabaseClient.rpc('has_admin_permission', { permission_key: 'manage_products' });
      return !error && allowed === true;
    }
    async function init() {
      if (!(await hasAccess())) { document.getElementById('accessDenied').style.display = 'block'; return; }
      document.getElementById('adminPage').style.display = 'block';
      document.getElementById('addNewBtn').addEventListener('click', () => openForm());
      document.getElementById('formCancelBtn').addEventListener('click', closeForm);
      document.getElementById('formSaveBtn').addEventListener('click', saveSection);
      await loadSections();
    }
    async function loadSections() {
      // Only ask for the newer columns once the catalog migration advertised them.
      let withIcons = false;
      try {
        const { data: marker } = await supabaseClient.from('settings').select('value').eq('key', 'catalog_icons_flag').maybeSingle();
        withIcons = !!(marker && String(marker.value).toLowerCase() === 'true');
      } catch (e) { withIcons = false; }
      const cols = withIcons
        ? 'id,name,display_order,is_active,created_at,description,icon_mode,icon_key,icon_image_url'
        : 'id,name,display_order,is_active,created_at';
      const res = await supabaseClient.from('store_sections').select(cols).order('display_order').order('name');
      if (res.error) { showNotice(errorText(res.error)); return; }
      sections = res.data || [];
      renderSections();
    }
    async function categoryCount(sectionId) {
      const { count, error } = await supabaseClient.from('categories').select('id', { count:'exact', head:true }).eq('section_id', sectionId);
      return error ? 0 : (count || 0);
    }
    async function renderSections() {
      const container = document.getElementById('sectionsList');
      if (!sections.length) { container.innerHTML = '<div class="empty-state"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-layers"></use></svg>لا توجد أقسام بعد. أضف أول قسم ليظهر في الصفحة الرئيسية.</div>'; return; }
      const counts = await Promise.all(sections.map(s => categoryCount(s.id)));
      container.innerHTML = sections.map((section, index) => `
        <div class="manage-item">
          <div class="manage-item-info">
            <div class="section-hero-icon" data-icon-slot="${section.id}" style="width: 44px;height: 44px;border-radius: 13px;font-size: 18px;margin-left: 12px;"></div>
            <div class="category-meta-text">
              <div class="manage-item-name">${escapeHtml(section.name)} ${!section.is_active ? '<span class="inactive-badge">مخفي</span>' : ''}</div>
              <div class="section-meta"><span>ترتيب: ${Number(section.display_order) || 0}</span><span>${counts[index]} تصنيف</span><span class="section-count">${section.is_active ? 'ظاهر في المتجر' : 'مؤرشف'}</span></div>
            </div>
          </div>
          <div class="manage-item-actions">
            <button class="admin-action-btn" data-action="edit" data-id="${section.id}" title="تعديل"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-pen"></use></svg></button>
            <button class="admin-action-btn" data-action="delete" data-id="${section.id}" title="حذف"><svg class="mm-i" style="color: var(--danger);" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-trash-2"></use></svg></button>
          </div>
        </div>`).join('');
      // fill each icon slot with the resolved icon (custom image or Lucide key)
      sections.forEach((section) => {
        const slot = container.querySelector('[data-icon-slot="' + section.id + '"]');
        if (!slot) return;
        const spec = window.MeemCategoryIcons ? window.MeemCategoryIcons.resolve(section) : { mode: 'auto', key: 'layout-grid' };
        if (spec.mode === 'custom' && spec.image) {
          const img = document.createElement('img');
          img.src = spec.image; img.alt = ''; img.width = 22; img.height = 22;
          img.addEventListener('error', () => { slot.replaceChildren(spriteIcon(spec.key)); }, { once: true });
          slot.replaceChildren(img);
        } else {
          slot.replaceChildren(spriteIcon(window.MeemCategoryIcons && window.MeemCategoryIcons.isValidKey(spec.key) ? spec.key : 'layout-grid'));
        }
      });
      container.querySelectorAll('[data-action="edit"]').forEach(btn => btn.addEventListener('click', () => openForm(btn.dataset.id)));
      container.querySelectorAll('[data-action="delete"]').forEach(btn => btn.addEventListener('click', () => deleteSection(btn.dataset.id)));
    }
    function spriteIcon(key) {
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.setAttribute('class', 'mm-i'); svg.setAttribute('aria-hidden', 'true');
      const use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
      use.setAttribute('href', 'assets/icons/lucide-sprite.svg#i-' + key);
      svg.appendChild(use); return svg;
    }
    let iconPicker = null;
    function mountIconPicker(section) {
      if (!window.MeemIconPicker) return;
      iconPicker = window.MeemIconPicker.mount(document.getElementById('iconPicker'), {
        row: section || {},
        nameProvider: () => nameInput.value
      });
    }
    function openForm(id = null) {
      editingId = id;
      formError.textContent = '';
      if (id) {
        const section = sections.find(item => item.id === id);
        document.getElementById('formModalTitle').textContent = 'تعديل القسم';
        nameInput.value = section?.name || '';
        orderInput.value = section?.display_order ?? 0;
        activeInput.value = String(section?.is_active !== false);
        mountIconPicker(section);
      } else {
        document.getElementById('formModalTitle').textContent = 'قسم جديد';
        nameInput.value = '';
        orderInput.value = sections.length;
        activeInput.value = 'true';
        mountIconPicker({});
      }
      formModal.classList.add('show');
      nameInput.focus();
    }
    function closeForm() { formModal.classList.remove('show'); editingId = null; }
    async function saveSection() {
      const name = nameInput.value.trim();
      if (!name) { formError.textContent = 'اكتب اسم القسم أولًا.'; return; }
      const button = document.getElementById('formSaveBtn');
      button.disabled = true; button.textContent = 'جاري الحفظ...'; formError.textContent = '';
      const payload = { name, display_order: Math.max(0, parseInt(orderInput.value, 10) || 0), is_active: activeInput.value === 'true' };
      try {
        let sectionId = editingId;
        if (editingId) {
          const response = await supabaseClient.from('store_sections').update(payload).eq('id', editingId);
          if (response.error) throw new Error(errorText(response.error));
        } else {
          const response = await supabaseClient.from('store_sections').insert(payload).select('id').single();
          if (response.error) throw new Error(errorText(response.error));
          sectionId = response.data.id;
        }
        if (iconPicker && sectionId) {
          const icon = await iconPicker.resolve();
          const { error: iconErr } = await supabaseClient.rpc('admin_set_section_icon', {
            p_id: sectionId, p_mode: icon.icon_mode, p_key: icon.icon_key, p_image: icon.icon_image_url
          });
          if (iconErr && iconErr.message && iconErr.message.indexOf('does not exist') === -1) {
            throw new Error('تم حفظ القسم لكن تعذر حفظ الأيقونة: ' + iconErr.message);
          }
        }
      } catch (e) {
        button.disabled = false; button.textContent = 'حفظ القسم';
        formError.textContent = e.message || 'تعذر الحفظ';
        return;
      }
      button.disabled = false; button.textContent = 'حفظ القسم';
      closeForm(); showNotice('تم حفظ القسم بنجاح.', 'success'); await loadSections();
    }
    async function deleteSection(id) {
      if (!confirm('هل تريد حذف هذا القسم؟ يجب نقل التصنيفات التابعة له أولًا.')) return;
      const { error } = await supabaseClient.from('store_sections').delete().eq('id', id);
      if (error) { showNotice(errorText(error)); return; }
      showNotice('تم حذف القسم.', 'success'); await loadSections();
    }
    init();
