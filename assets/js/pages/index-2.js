// ---------- Drawer ----------
const drawerOverlay = document.getElementById('drawerOverlay');
document.getElementById('openDrawerBtn').addEventListener('click', () => {
  drawerOverlay.classList.add('show');
  loadDrawer();
});
document.getElementById('closeDrawerBtn').addEventListener('click', () => {
  drawerOverlay.classList.remove('show');
});
drawerOverlay.addEventListener('click', (e) => {
  if (e.target === drawerOverlay) drawerOverlay.classList.remove('show');
});
document.getElementById('drawerLogoutBtn').addEventListener('click', async (event) => {
  const button = event.currentTarget;
  button.disabled = true;

  try {
    const { error } = await supabaseClient.auth.signOut();
    if (error) throw error;
    window.location.href = 'index.html';
  } catch (error) {
    button.disabled = false;
    alert('تعذر تسجيل الخروج حالياً. حاول مرة أخرى.');
  }
});

async function loadDrawer() {
  const guestBox = document.getElementById('drawerGuestBox');
  const userBox = document.getElementById('drawerUserBox');
  const adminLinkBox = document.getElementById('adminLinkBox');
  const adminDividerBox = document.getElementById('adminDividerBox');

  adminLinkBox.style.display = 'none';
  adminDividerBox.style.display = 'none';

  try {
    const { data: { session }, error: sessionError } = await supabaseClient.auth.getSession();
    if (sessionError) throw sessionError;

    if (!session) {
      guestBox.style.display = 'block';
      userBox.style.display = 'none';
      return;
    }

    guestBox.style.display = 'none';
    userBox.style.display = 'block';
    document.getElementById('drawerEmail').textContent = session.user.email || '';

    const [{ data: profile, error: profileError }, { data: wallet, error: walletError }] = await Promise.all([
      supabaseClient.from('profiles').select('full_name, role, avatar_url').eq('id', session.user.id).maybeSingle(),
      supabaseClient.from('wallets').select('balance').eq('user_id', session.user.id).maybeSingle()
    ]);

    if (profileError || walletError) throw profileError || walletError;

    document.getElementById('drawerGreeting').textContent = profile?.full_name
      ? `مرحباً، ${profile.full_name}`
      : 'مرحباً بك يا لاعب';

    const drawerAvatarImg = document.getElementById('drawerAvatarImg');
    const drawerAvatarIcon = document.querySelector('#drawerAvatar > svg');
    if (drawerAvatarImg && profile?.avatar_url) {
      drawerAvatarImg.src = profile.avatar_url;
      drawerAvatarImg.hidden = false;
      if (drawerAvatarIcon) drawerAvatarIcon.style.display = 'none';
    } else if (drawerAvatarImg) {
      drawerAvatarImg.hidden = true;
      if (drawerAvatarIcon) drawerAvatarIcon.style.display = '';
    }

    if (profile?.role === 'admin') {
      adminLinkBox.style.display = 'block';
      adminDividerBox.style.display = 'block';
    }

    document.getElementById('drawerBalance').textContent =
      `${formatSDG(wallet?.balance ?? 0)} ج.س`;
  } catch (error) {
    guestBox.style.display = 'block';
    userBox.style.display = 'none';
  }
}

// ---------- جلب وعرض كروت الألعاب الموحدة ----------
async function init() {
  try {
    const { data: { session }, error: sessionError } = await supabaseClient.auth.getSession();
    if (sessionError) throw sessionError;

    if (session) {
      const { count, error: notificationError } = await supabaseClient
        .from('notifications')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', session.user.id)
        .eq('is_read', false);

      if (!notificationError && count > 0) {
        document.getElementById('notifDot').style.display = 'block';
      }
    }

    // Ask the capability marker first so we never request a column that is not
    // there yet (an unknown column makes PostgREST answer 400).
    let withIcons = false;
    try {
      const { data: marker } = await supabaseClient
        .from('settings').select('value').eq('key', 'catalog_icons_flag').maybeSingle();
      withIcons = !!(marker && String(marker.value).toLowerCase() === 'true');
    } catch (e) { withIcons = false; }

    const SECTIONS_FULL = 'id,name,display_order,description';
    const SECTIONS_BASE = 'id,name,display_order';
    const CATS_FULL = 'id,section_id,name,description,image_url,display_order,icon_mode,icon_key,icon_image_url';
    const CATS_BASE = 'id,section_id,name,description,image_url,display_order';

    const [ sectionsRes, categoriesRes, productsRes ] = await Promise.all([
      supabaseClient.from('store_sections').select(withIcons ? SECTIONS_FULL : SECTIONS_BASE)
        .eq('is_active', true).order('display_order').order('name'),
      supabaseClient.from('categories').select(withIcons ? CATS_FULL : CATS_BASE)
        .eq('is_active', true).not('section_id', 'is', null).order('display_order').order('name'),
      supabaseClient.from('products').select('category_id').eq('is_active', true)
    ]);

    const sections = sectionsRes.data, sectionsError = sectionsRes.error;
    const categories = categoriesRes.data, categoriesError = categoriesRes.error;
    const products = productsRes.data, productsError = productsRes.error;

    if (sectionsError) throw sectionsError;
    if (categoriesError) throw categoriesError;
    // عدّاد المنتجات داخل كل قسم تحسين عرض فقط — لا نُفشل الصفحة إن تعذّر جلبه
    if (productsError && typeof devWarn === 'function') devWarn('[MEEM] products count unavailable:', productsError.message);
    renderCatalog(sections || [], categories || [], products || []);
  } catch (error) {
    renderMessage('تعذر تحميل الألعاب حالياً', 'تحقق من اتصالك ثم أعد المحاولة.');
  }
}

function renderMessage(title, description) {
  const container = document.getElementById('categoriesContainer');
  const state = document.createElement('div');
  const heading = document.createElement('h3');
  const text = document.createElement('p');

  state.className = 'empty-state';
  state.style.cssText = 'padding:40px 20px; text-align:center; grid-column:1 / -1;';
  const mark = document.createElement('img');
  mark.className = 'empty-state__mark';
  mark.src = 'assets/img/meem-mark-96.png';
  mark.alt = '';
  mark.setAttribute('aria-hidden', 'true');
  mark.width = 48;
  mark.height = 48;
  heading.textContent = title;
  text.textContent = description;
  text.style.color = 'var(--text-muted)';
  state.append(mark, heading, text);
  container.replaceChildren(state);
}

function getSafeImageUrl(value) {
  if (typeof value !== 'string' || !value.trim()) return null;

  try {
    const url = new URL(value, window.location.href);
    return url.protocol === 'https:' || url.protocol === 'http:' ? url.href : null;
  } catch (error) {
    return null;
  }
}

function createIcon(name, style) {
  // Single icon system: Lucide sprite (see assets/icons/lucide-sprite.svg)
  const icon = window.rzIcon(name);
  if (style) icon.style.cssText = style;
  return icon;
}

// Resolve the icon for a section/category row via the shared module. Missing
// icon columns (before the migration) simply resolve to the smart auto icon.
function iconSpec(row) {
  if (window.MeemCategoryIcons) return window.MeemCategoryIcons.resolve(row);
  return { mode: 'auto', key: 'gamepad-2', image: '' };
}

// The unified icon frame (blue gradient + thin gold edge). Accepts an optional
// custom image (rendered inside the same frame) or falls back to a sprite icon.
function createIconBox(spec, extraClass) {
  const box = document.createElement('span');
  box.className = 'mm-ico' + (extraClass ? ' ' + extraClass : '');
  box.setAttribute('aria-hidden', 'true');
  if (spec.mode === 'custom' && spec.image) {
    const url = getSafeImageUrl(spec.image);
    if (url) {
      const img = document.createElement('img');
      img.src = url;
      img.alt = '';
      img.loading = 'lazy';
      img.decoding = 'async';
      img.addEventListener('error', () => { box.replaceChildren(createIcon(spec.key || 'layout-grid')); }, { once: true });
      box.appendChild(img);
      return box;
    }
  }
  const key = (window.MeemCategoryIcons && window.MeemCategoryIcons.isValidKey(spec.key))
    ? spec.key : 'layout-grid';
  box.appendChild(createIcon(key));
  return box;
}

function createCategoryCard(cat) {
    const name = typeof cat.name === 'string' && cat.name.trim() ? cat.name.trim() : 'تصنيف';
    const description = typeof cat.description === 'string' && cat.description.trim()
      ? cat.description.trim() : '';
    const imageUrl = getSafeImageUrl(cat.image_url);
    const spec = iconSpec(cat);
    const card = document.createElement('a');
    const info = document.createElement('div');
    const nameElement = document.createElement('div');

    card.href = `category.html?id=${encodeURIComponent(String(cat.id))}`;
    card.className = 'game-card';
    card.setAttribute('aria-label', `فتح تصنيف ${name}`);

    // Cover image if the admin set one, otherwise the unified icon frame.
    if (imageUrl) {
      const thumb = document.createElement('div');
      thumb.className = 'game-thumb';
      const image = document.createElement('img');
      image.src = imageUrl;
      image.alt = name;
      image.loading = 'lazy';
      image.decoding = 'async';
      image.addEventListener('error', () => {
        const frame = document.createElement('div');
        frame.className = 'game-thumb game-thumb--icon';
        frame.appendChild(createIconBox(spec));
        thumb.replaceWith(frame);
      }, { once: true });
      thumb.appendChild(image);
      card.appendChild(thumb);
    } else {
      const thumb = document.createElement('div');
      thumb.className = 'game-thumb game-thumb--icon';
      thumb.appendChild(createIconBox(spec));
      card.appendChild(thumb);
    }

    info.className = 'game-info';
    nameElement.className = 'game-name';
    nameElement.textContent = name;
    info.appendChild(nameElement);
    if (description) {
      const descriptionElement = document.createElement('div');
      descriptionElement.className = 'game-desc';
      descriptionElement.textContent = description;
      descriptionElement.title = description;
      info.appendChild(descriptionElement);
    }
    card.append(info);
    return card;
}

/* الأيقونة الذكية للأقسام عبر الوحدة المشتركة (نفس منطق الأدمن). */
function sectionIconFor(name, row) {
  if (window.MeemCategoryIcons) {
    if (row && (row.icon_mode || row.icon_key)) return window.MeemCategoryIcons.resolve(row).key;
    return window.MeemCategoryIcons.suggest(name);
  }
  return 'layers';
}

function renderCatalog(sections, categories, products) {
  const container = document.getElementById('categoriesContainer');
  container.className = 'catalog-sections';

  const productCountByCategory = new Map();
  (products || []).forEach((product) => {
    if (!product || product.category_id == null) return;
    productCountByCategory.set(product.category_id, (productCountByCategory.get(product.category_id) || 0) + 1);
  });

  if (sections.length === 0 || categories.length === 0) {
    renderMessage('لا توجد أقسام أو تصنيفات متاحة حالياً', 'أضف قسمًا ثم اربط به التصنيفات من لوحة الأدمن.');
    return;
  }

  const fragment = document.createDocumentFragment();
  let renderedSections = 0;
  sections.forEach((section) => {
    const sectionCategories = categories.filter(category => category.section_id === section.id);
    if (!sectionCategories.length) return;
    renderedSections += 1;
    const sectionElement = document.createElement('section');
    sectionElement.className = 'store-section';
    sectionElement.setAttribute('aria-labelledby', `section-title-${section.id}`);
    const sectionProductCount = sectionCategories.reduce(
      (sum, category) => sum + (productCountByCategory.get(category.id) || 0), 0
    );

    const heading = document.createElement('div');
    heading.className = 'store-section-heading';
    const iconWrap = createIconBox(iconSpec(section));
    const titles = document.createElement('div');
    titles.className = 'store-section-titles';
    const kicker = document.createElement('span');
    kicker.className = 'store-section-kicker';
    kicker.textContent = 'MEEM COLLECTION';
    const title = document.createElement('h2');
    title.id = `section-title-${section.id}`;
    title.className = 'store-section-title';
    title.textContent = section.name;
    titles.append(kicker, title);
    const countBadge = document.createElement('span');
    countBadge.className = 'store-section-count';
    countBadge.textContent = `${sectionProductCount} منتج`;
    heading.append(iconWrap, titles, countBadge);

    // The description is admin-authored and optional: it disappears when empty.
    const descriptionText = typeof section.description === 'string' ? section.description.trim() : '';

    const grid = document.createElement('div');
    grid.className = 'categories-grid';
    sectionCategories.forEach(category => grid.appendChild(createCategoryCard(category)));
    if (descriptionText) {
      const description = document.createElement('p');
      description.className = 'store-section-description';
      description.textContent = descriptionText;
      sectionElement.append(heading, description, grid);
    } else {
      sectionElement.append(heading, grid);
    }
    fragment.appendChild(sectionElement);
  });

  if (!renderedSections) {
    renderMessage('لا توجد تصنيفات مرتبطة بالأقسام حالياً', 'من لوحة الأدمن: أنشئ قسمًا ثم اختره عند إضافة التصنيف.');
    return;
  }
  container.replaceChildren(fragment);
  renderSectionRow(sections);
  renderHighlights();
}

function renderSectionRow(sections) {
  const host = document.getElementById('sectionRow');
  if (!host) return;
  if (!sections || !sections.length) { host.hidden = true; return; }
  const frag = document.createDocumentFragment();
  sections.forEach((section) => {
    const chip = document.createElement('a');
    chip.className = 'section-chip';
    chip.href = '#section-title-' + section.id;
    chip.setAttribute('aria-label', 'انتقل إلى قسم ' + section.name);
    chip.appendChild(createIconBox(iconSpec(section)));
    const label = document.createElement('span');
    label.className = 'section-chip-label';
    label.textContent = section.name;
    chip.appendChild(label);
    chip.addEventListener('click', function (e) {
      const target = document.getElementById('section-title-' + section.id);
      if (target) { e.preventDefault(); target.scrollIntoView({ behavior: 'smooth', block: 'start' }); }
    });
    frag.appendChild(chip);
  });
  host.replaceChildren(frag);
  host.hidden = false;
}

function createProductCard(p, rate) {
  const name = typeof p.name === 'string' && p.name.trim() ? p.name.trim() : 'منتج';
  const price = Math.max(0, Number(p.price_usd) || 0);
  const card = document.createElement('a');
  card.className = 'game-card prod-card';
  card.href = 'product.html?id=' + encodeURIComponent(String(p.id));
  card.setAttribute('aria-label', 'فتح ' + name);
  const thumb = document.createElement('div');
  thumb.className = 'game-thumb';
  const url = getSafeImageUrl(p.image_url);
  if (url) {
    const img = document.createElement('img');
    img.src = url; img.alt = name; img.loading = 'lazy'; img.decoding = 'async';
    img.addEventListener('error', () => {
      const frame = document.createElement('div');
      frame.className = 'game-thumb game-thumb--icon';
      frame.appendChild(createIconBox({ mode: 'auto', key: 'package' }));
      thumb.replaceWith(frame);
    }, { once: true });
    thumb.appendChild(img);
  } else {
    thumb.className = 'game-thumb game-thumb--icon';
    thumb.appendChild(createIconBox({ mode: 'auto', key: 'package' }));
  }
  const info = document.createElement('div');
  info.className = 'game-info';
  const nm = document.createElement('div'); nm.className = 'game-name'; nm.textContent = name;
  const pr = document.createElement('div'); pr.className = 'prod-price';
  pr.textContent = (typeof formatSDG === 'function' ? formatSDG(price * (rate || 1)) : price.toFixed(2)) + ' ج.س';
  info.append(nm, pr);
  card.append(thumb, info);
  return card;
}

async function renderHighlights() {
  const host = document.getElementById('homeHighlights');
  if (!host) return;
  host.replaceChildren();
  // capability marker: only render once the functions exist on the backend
  let flag = false;
  try {
    const { data } = await supabaseClient.from('settings').select('value').eq('key', 'home_highlights_flag').maybeSingle();
    flag = !!(data && String(data.value).toLowerCase() === 'true');
  } catch (e) { flag = false; }
  if (!flag) return;

  let rate = 1;
  try { rate = Number(await getExchangeRate()) || 1; } catch (e) { rate = 1; }

  const [newestRes, topRes] = await Promise.all([
    supabaseClient.from('products').select('id,name,image_url,price_usd,created_at')
      .eq('is_active', true).order('created_at', { ascending: false }).limit(8),
    supabaseClient.rpc('get_top_ordered_products', { p_limit: 8 })
  ]);

  const top = (() => {
    let d = topRes && topRes.data;
    if (typeof d === 'string') { try { d = JSON.parse(d); } catch (e) { d = []; } }
    return Array.isArray(d) ? d : [];
  })();
  const newest = (newestRes && !newestRes.error && Array.isArray(newestRes.data)) ? newestRes.data : [];

  const frag = document.createDocumentFragment();
  if (top.length) frag.appendChild(buildHighlightSection('الأكثر طلباً', 'flame', top, rate, true));
  if (newest.length) frag.appendChild(buildHighlightSection('جديد في MEEM', 'sparkles', newest, rate, false));
  host.appendChild(frag);
}

function buildHighlightSection(title, iconKey, products, rate, withCount) {
  const section = document.createElement('section');
  section.className = 'store-section hl-section';
  const heading = document.createElement('div');
  heading.className = 'store-section-heading';
  heading.appendChild(createIconBox({ mode: 'preset', key: iconKey }));
  const titles = document.createElement('div');
  titles.className = 'store-section-titles';
  const h = document.createElement('h2');
  h.className = 'store-section-title';
  h.textContent = title;
  titles.appendChild(h);
  heading.appendChild(titles);
  const grid = document.createElement('div');
  grid.className = 'categories-grid';
  products.forEach((p) => {
    const card = createProductCard(p, rate);
    if (withCount && p.ordered && Number(p.ordered) > 0) {
      const c = document.createElement('div');
      c.className = 'prod-count';
      c.textContent = 'طلب ' + Number(p.ordered).toLocaleString('ar-EG') + ' مرة';
      const info = card.querySelector('.game-info');
      if (info) info.appendChild(c);
    }
    grid.appendChild(card);
  });
  section.append(heading, grid);
  return section;
}

init();
