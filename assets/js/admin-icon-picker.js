/* =========================================================
   MEEM STORE — admin icon picker (sections & categories)
   Modes: automatic | preset (Lucide library) | custom image.
   Custom images: PNG/JPG/WEBP only (no SVG), cropped & resized to
   256x256 WebP < 100KB in the browser, uploaded to category-icons.
   Requires: assets/js/category-icons.js (window.MeemCategoryIcons).
   Exposes window.MeemIconPicker.mount(host, { row, nameProvider }).
   ========================================================= */
(function () {
  'use strict';
  var CI = window.MeemCategoryIcons;
  var MAX_BYTES = 100 * 1024;
  var ALLOWED = ['image/jpeg', 'image/png', 'image/webp'];

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }
  function iconSvg(key, cls) {
    var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('class', cls || 'mm-i');
    svg.setAttribute('aria-hidden', 'true');
    var use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
    use.setAttribute('href', 'assets/icons/lucide-sprite.svg#i-' + key);
    svg.appendChild(use);
    return svg;
  }
  function frame(key, image, size) {
    var box = el('span', 'mm-ico');
    box.style.setProperty('--mm-ico-size', size + 'px');
    box.setAttribute('aria-hidden', 'true');
    if (image) {
      var img = el('img'); img.src = image; img.alt = ''; img.decoding = 'async';
      img.addEventListener('error', function () { box.replaceChildren(iconSvg(key || 'layout-grid')); }, { once: true });
      box.appendChild(img);
    } else {
      box.appendChild(iconSvg(CI && CI.isValidKey(key) ? key : 'layout-grid'));
    }
    return box;
  }

  function loadImage(file) {
    return new Promise(function (resolve, reject) {
      var img = new Image();
      img.onload = function () { resolve(img); };
      img.onerror = function () { reject(new Error('تعذر قراءة ملف الصورة')); };
      img.src = URL.createObjectURL(file);
    });
  }
  function toSquareWebp(img) {
    return new Promise(function (resolve, reject) {
      var S = 256;
      var c = document.createElement('canvas');
      c.width = S; c.height = S;
      var ctx = c.getContext('2d');
      var side = Math.min(img.width, img.height);
      var sx = (img.width - side) / 2, sy = (img.height - side) / 2;
      ctx.clearRect(0, 0, S, S);
      ctx.drawImage(img, sx, sy, side, side, 0, 0, S, S);
      var attempt = function (q) {
        c.toBlob(function (blob) {
          if (!blob) { reject(new Error('تعذر تصدير الصورة')); return; }
          if (blob.size <= MAX_BYTES || q <= 0.5) { resolve(blob); return; }
          attempt(Math.round((q - 0.07) * 100) / 100);
        }, 'image/webp', q);
      };
      attempt(0.9);
    });
  }

  function mount(host, opts) {
    opts = opts || {};
    var row = opts.row || {};
    var state = {
      mode: (row.icon_mode === 'preset' || row.icon_mode === 'custom') ? row.icon_mode : 'auto',
      key: row.icon_key || '',
      imageUrl: row.icon_image_url || '',
      blob: null,
      localUrl: ''
    };

    host.replaceChildren();
    host.classList.add('mm-icon-picker');

    // header: live preview + mode segmented control
    var head = el('div', 'mip-head');
    var previewWrap = el('div', 'mip-preview');
    var seg = el('div', 'mip-seg');

    function currentSpec() {
      var name = opts.nameProvider ? opts.nameProvider() : (row.name || '');
      if (state.mode === 'preset' && CI && CI.isValidKey(state.key)) return { mode: 'preset', key: state.key };
      if (state.mode === 'custom' && state.imageUrl) return { mode: 'custom', image: state.imageUrl, key: CI ? CI.suggest(name) : 'layout-grid' };
      return { mode: 'auto', key: CI ? CI.suggest(name) : 'layout-grid' };
    }
    function renderPreview() {
      var spec = currentSpec();
      previewWrap.replaceChildren(frame(spec.key, spec.mode === 'custom' ? spec.image : '', 64));
      var label = el('span', 'mip-preview-label');
      label.textContent = spec.mode === 'auto' ? ('تلقائي: ' + spec.key)
        : spec.mode === 'preset' ? ('مختار: ' + spec.key) : 'صورة مخصصة';
      previewWrap.appendChild(label);
    }
    function renderSeg() {
      seg.replaceChildren();
      [['auto', 'تلقائي'], ['preset', 'من المكتبة'], ['custom', 'رفع صورة']].forEach(function (pair) {
        var b = el('button', 'mip-seg-btn' + (state.mode === pair[0] ? ' active' : ''), pair[1]);
        b.type = 'button';
        b.addEventListener('click', function () {
          state.mode = pair[0];
          if (state.mode === 'custom' && !state.imageUrl) state.imageUrl = state.localUrl || '';
          if (state.mode === 'preset' && !state.key && CI) state.key = CI.suggest(opts.nameProvider ? opts.nameProvider() : row.name);
          renderSeg(); renderBody(); renderPreview();
          if (opts.onChange) opts.onChange(getValue());
        });
        seg.appendChild(b);
      });
    }

    // body depends on the mode
    var body = el('div', 'mip-body');
    function renderBody() {
      body.replaceChildren();
      if (state.mode === 'auto') {
        body.appendChild(el('p', 'mip-note', 'يُختار تلقائياً حسب اسم القسم/التصنيف. اكتب الاسم لتحديثه.'));
        return;
      }
      if (state.mode === 'preset') { renderLibrary(); return; }
      renderUpload();
    }

    function renderLibrary() {
      var search = el('input', 'mip-search');
      search.type = 'search';
      search.placeholder = 'ابحث بالعربي أو الإنجليزي…';
      var grid = el('div', 'mip-grid');
      function paint(q) {
        grid.replaceChildren();
        var query = (q || '').toLowerCase();
        var suggested = query && CI ? CI.suggest(query, '') : '';
        (CI ? CI.PRESETS : []).forEach(function (key) {
          if (query && key.indexOf(query) === -1 && key !== suggested) return;
          var b = el('button', 'mip-cell' + (state.key === key ? ' active' : ''));
          b.type = 'button';
          b.title = key;
          b.setAttribute('aria-label', key);
          b.setAttribute('aria-pressed', state.key === key ? 'true' : 'false');
          b.appendChild(frame(key, '', 40));
          b.addEventListener('click', function () {
            state.key = key;
            grid.querySelectorAll('.mip-cell').forEach(function (c) { c.classList.remove('active'); c.setAttribute('aria-pressed', 'false'); });
            b.classList.add('active'); b.setAttribute('aria-pressed', 'true');
            renderPreview();
            if (opts.onChange) opts.onChange(getValue());
          });
          grid.appendChild(b);
        });
        if (!grid.children.length) grid.appendChild(el('p', 'mip-note', 'لا نتائج — جرّب كلمة أخرى.'));
      }
      search.addEventListener('input', function () { paint(search.value.trim()); });
      body.append(search, grid);
      paint('');
    }

    function renderUpload() {
      var input = document.createElement('input');
      input.type = 'file';
      input.accept = 'image/png,image/jpeg,image/webp';
      input.id = 'mipFile_' + Math.random().toString(36).slice(2, 7);
      var label = el('label', 'mip-upload');
      label.setAttribute('for', input.id);
      label.appendChild(el('span', null, 'اختر صورة (PNG/JPG/WEBP)'));
      var note = el('p', 'mip-note', state.imageUrl ? 'الصورة الحالية محفوظة. اختر صورة جديدة لاستبدالها.' : 'تُقصّ وتُصغَّر تلقائياً إلى 256×256 WebP أقل من 100KB.');
      var thumbWrap = el('div', 'mip-thumb');
      if (state.imageUrl) thumbWrap.appendChild(frame(null, state.imageUrl, 56));

      input.addEventListener('change', async function (e) {
        var file = e.target.files && e.target.files[0];
        if (!file) return;
        try {
          if (ALLOWED.indexOf(file.type) === -1) throw new Error('صيغة غير مدعومة (PNG/JPG/WEBP فقط، بدون SVG)');
          if (file.size > 12 * 1024 * 1024) throw new Error('الملف كبير جداً (الحد 12MB)');
          var img = await loadImage(file);
          var blob = await toSquareWebp(img);
          if (blob.size > MAX_BYTES) throw new Error('الصورة أكبر من 100KB بعد الضغط');
          if (state.localUrl) URL.revokeObjectURL(state.localUrl);
          state.blob = blob;
          state.localUrl = URL.createObjectURL(blob);
          state.imageUrl = state.localUrl;
          note.textContent = 'جاهزة للرفع: ' + Math.round(blob.size / 1024) + ' KB / 100 KB';
          note.style.color = '';
          thumbWrap.replaceChildren(frame(null, state.localUrl, 56));
          renderPreview();
          if (opts.onChange) opts.onChange(getValue());
        } catch (err) {
          note.textContent = err.message;
          note.style.color = 'var(--danger)';
        }
      });
      body.append(label, input, note, thumbWrap);
      input.style.display = 'none';
    }

    function getValue() {
      var spec = currentSpec();
      return {
        icon_mode: state.mode,
        icon_key: state.mode === 'preset' ? state.key : null,
        icon_image_url: state.mode === 'custom' ? state.imageUrl : null
      };
    }

    // Upload the pending blob (if any) and return the final values.
    async function resolve() {
      var v = getValue();
      if (v.icon_mode === 'custom' && state.imageUrl && state.blob) {
        if (!window.supabaseClient || !window.supabaseClient.storage) throw new Error('تخزين الصور غير متاح');
        var path = 'icons/' + Date.now() + '-' + Math.random().toString(36).slice(2, 8) + '.webp';
        var up = await window.supabaseClient.storage.from('category-icons').upload(path, state.blob, { contentType: 'image/webp' });
        if (up.error) throw new Error('فشل رفع الصورة: ' + up.error.message);
        var pub = window.supabaseClient.storage.from('category-icons').getPublicUrl(path);
        v.icon_image_url = pub.data.publicUrl;
        state.blob = null;
      }
      return v;
    }

    head.append(previewWrap, seg);
    host.append(head, body);
    renderSeg(); renderBody(); renderPreview();

    return {
      getValue: getValue,
      resolve: resolve,
      refresh: function () { renderPreview(); }
    };
  }

  window.MeemIconPicker = { mount: mount };
})();
