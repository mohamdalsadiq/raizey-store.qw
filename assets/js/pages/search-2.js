let rate = 0;
let searchTimeout = null;
let latestSearchId = 0;

function sanitizeSearchTerm(value) {
  return String(value || '')
    .normalize('NFKC')
    .replace(/[\u0000-\u001F\u007F<>%_\\,()]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 80);
}

async function init() {
  rate = await getExchangeRate();

  const params = new URLSearchParams(window.location.search);
  const initialQuery = sanitizeSearchTerm(params.get('q'));
  document.getElementById('searchInput').value = initialQuery;

  if (initialQuery) await search(initialQuery);

  document.getElementById('searchInput').addEventListener('input', (e) => {
    // تركيز وتأثير إضاءة الحدود
    e.target.style.borderColor = e.target.value ? 'var(--accent-gold)' : 'var(--border-color)';

    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(() => search(e.target.value), 400);
  });
}

async function search(query) {
  const productsGrid = document.getElementById('productsGrid');
  const categoriesGrid = document.getElementById('categoriesGrid');
  const resultsTitle = document.getElementById('resultsTitle');
  const categoriesTitle = document.getElementById('categoriesTitle');
  const safeQuery = sanitizeSearchTerm(query);
  const searchId = ++latestSearchId;

  if (!safeQuery) {
    resultsTitle.textContent = 'اكتب اسم اللعبة أو الباقة اللي تدور عليها';
    categoriesTitle.style.display = 'none';
    productsGrid.innerHTML = '';
    categoriesGrid.innerHTML = '';
    return;
  }

  resultsTitle.textContent = 'جارِ البحث الفوري...';
  categoriesTitle.style.display = 'none';
  categoriesGrid.innerHTML = '';

  try {
    const [categoriesResponse, productsResponse] = await Promise.all([
      supabaseClient
        .from('categories')
        .select('*')
        .eq('is_active', true)
        .ilike('name', `%${safeQuery}%`)
        .order('display_order'),
      supabaseClient
        .from('products')
        .select('*')
        .eq('is_active', true)
        .ilike('name', `%${safeQuery}%`)
        .order('display_order')
    ]);

    if (searchId !== latestSearchId) return;
    if (categoriesResponse.error || productsResponse.error) throw new Error('search_failed');

    const categories = categoriesResponse.data;
    const products = productsResponse.data;
    const productResults = (products || []).map(p => ({ ...p, price_sdg: Number(p.price_usd) * Number(rate) }));
    const categoryResults = categories || [];

    // إعداد وضبط عناوين النتائج والمجاميع
    if (categoryResults.length === 0 && productResults.length === 0) {
      resultsTitle.textContent = 'لا توجد نتائج مطابقة، تأكد من كتابة الاسم الصحيح';
      productsGrid.innerHTML = '';
      return;
    }

    // عرض الألعاب/التصنيفات الموحدة إذا وُجدت
    if (categoryResults.length > 0) {
      categoriesTitle.style.display = 'block';
      categoriesTitle.textContent = `الألعاب والخدمات المطابقة (${categoryResults.length})`;

      categoriesGrid.innerHTML = categoryResults.map(cat => {
        const imgHtml = cat.image_url
          ? `<img src="${escapeAttribute(sanitizeUrl(cat.image_url))}" alt="${escapeAttribute(cat.name)}" loading="lazy">`
          : `<div style="color: var(--mm-text-muted); font-size: 32px;"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-gamepad-2"></use></svg></div>`;
        const descText = escapeHtml(cat.description ? cat.description : 'تصفح الباقات والشدات المتوفرة حصرياً');

        return `
          <a href="category.html?id=${encodeURIComponent(cat.id)}" class="game-card">
            <div class="game-thumb">${imgHtml}</div>
            <div class="game-info">
              <div class="game-name">${escapeHtml(cat.name)}</div>
              <div class="game-desc" title="${descText}">${descText}</div>
              <div class="game-btn">
                <span>عرض الباقات</span>
                <svg class="mm-i" style="font-size: 10px;" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-chevron-left"></use></svg>
              </div>
            </div>
          </a>
        `;
      }).join('');
    }

    // عرض باقات الشحن المباشرة المطابقة
    if (productResults.length > 0) {
      resultsTitle.textContent = `باقات الشحن المباشرة المطابقة (${productResults.length})`;
      productsGrid.innerHTML = productResults.map(p => `
        <a href="category.html?id=${encodeURIComponent(p.category_id)}" class="voucher-card">
          <div class="voucher-top">
            <div class="voucher-thumb">
              ${p.image_url ? `<img src="${escapeAttribute(sanitizeUrl(p.image_url))}" alt="${escapeAttribute(p.name)}" loading="lazy">` : '<div style="color: var(--mm-text-muted); font-size: 24px;"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-package"></use></svg></div>'}
            </div>
            <div class="voucher-name">${escapeHtml(p.name)}</div>
          </div>
          <div class="voucher-divider"></div>
          <div class="voucher-bottom">
            <div class="voucher-price">${formatSDG(p.price_sdg)} <small>ج.س</small></div>
            <div class="buy-btn">اشترِ</div>
          </div>
        </a>
      `).join('');
    } else {
      resultsTitle.textContent = categoryResults.length > 0 ? 'نتائج باقات الشحن الفردية' : '';
      productsGrid.innerHTML = categoryResults.length > 0 ? `<div style="color: var(--text-muted); font-size: 13px; padding: 10px 20px;">اضغط على اللعبة في الأعلى لعرض كافة باقاتها المتوفرة.</div>` : '';
    }

  } catch (err) {
    console.error(err);
    resultsTitle.textContent = 'حدث خطأ غير متوقع أثناء البحث.';
  }
}

init();
