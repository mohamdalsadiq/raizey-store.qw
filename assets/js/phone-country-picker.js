(function () {
  'use strict';
  let loading;
  function library() {
    if (window.libphonenumber) return Promise.resolve(window.libphonenumber);
    if (!loading) loading = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = 'assets/vendor/libphonenumber-max-1.13.15.js';
      script.onload = () => resolve(window.libphonenumber);
      script.onerror = () => { loading = null; script.remove(); reject(new Error('phone_library_unavailable')); };
      document.head.appendChild(script);
    });
    return loading;
  }
  function el(tag, cls, text) {
    const n = document.createElement(tag); if (cls) n.className = cls;
    if (text) n.textContent = text; return n;
  }
  function digits(value) {
    return String(value).replace(/[٠-٩۰-۹]/g, c => String(c.charCodeAt(0) - (c <= '٩' ? 1632 : 1776)));
  }
  function flag(iso) { return [...iso].map(c => String.fromCodePoint(c.charCodeAt(0) + 127397)).join(''); }
  function searchText(value) { return digits(value).toLowerCase().replace(/[أإآ]/g, 'ا').replace(/[\u064b-\u065f]/g, '').replace(/^\+/, ''); }
  async function create(root, phone) {
    const lib = await library();
    const names = new Intl.DisplayNames(['ar'], { type: 'region' });
    const english = new Intl.DisplayNames(['en'], { type: 'region' });
    const countries = lib.getCountries().filter(iso => iso !== 'IL').map(iso => ({ iso,
      name: iso === 'PS' ? 'فلسطين الحرة' : names.of(iso), english: english.of(iso), dial: lib.getCountryCallingCode(iso) }));
    countries.sort((a, b) => a.name.localeCompare(b.name, 'ar'));
    let current = countries.find(c => c.iso === 'SD');
    root.replaceChildren(); root.className = 'wa-country';
    const label = el('label', '', 'الدولة'); label.htmlFor = 'waCountryButton';
    const button = el('button', 'wa-country-button'); button.id = 'waCountryButton'; button.type = 'button';
    button.setAttribute('aria-haspopup', 'dialog'); button.setAttribute('aria-expanded', 'false');
    button.setAttribute('aria-controls', 'waCountryPopup');
    const popup = el('div', 'wa-country-popup'); popup.id = 'waCountryPopup'; popup.hidden = true;
    popup.setAttribute('role', 'dialog'); popup.setAttribute('aria-label', 'اختيار الدولة');
    const search = el('input'); search.type = 'search'; search.placeholder = 'ابحث بالدولة أو رمز الاتصال';
    search.setAttribute('aria-label', 'ابحث بالدولة أو رمز الاتصال'); search.autocomplete = 'off';
    const list = el('div', 'wa-country-list');
    popup.append(search, list); root.append(label, button, popup);
    function renderButton() {
      button.replaceChildren(el('span', 'wa-flag', flag(current.iso)), el('span', 'wa-country-name', current.name), el('bdi', 'wa-dial', '+' + current.dial), el('span', '', '⌄'));
      phone.placeholder = current.iso === 'SD' ? '912 345 678' : current.iso === 'SA' ? '50 123 4567' : 'رقم الهاتف داخل الدولة';
      phone.setAttribute('aria-label', 'رقم واتساب في ' + current.name);
    }
    function close() { popup.hidden = true; button.setAttribute('aria-expanded', 'false'); }
    function render(query) {
      const q = searchText(query); list.replaceChildren();
      countries.filter(c => !q || searchText(c.name + ' ' + c.english + ' ' + c.iso).includes(q) || c.dial.startsWith(q)).forEach(c => {
        const option = el('button', 'wa-country-option'); option.type = 'button'; option.dataset.country = c.iso;
        option.setAttribute('aria-pressed', String(current.iso === c.iso));
        option.append(el('span', 'wa-flag', flag(c.iso)), el('span', 'wa-country-name', c.name), el('bdi', 'wa-dial', '+' + c.dial));
        option.onclick = () => { current = c; renderButton(); close(); phone.dispatchEvent(new Event('input')); phone.focus(); };
        list.appendChild(option);
      });
      if (!list.children.length) list.appendChild(el('p', '', 'لا توجد دولة مطابقة للبحث.'));
    }
    button.onclick = () => {
      if (!popup.hidden) { close(); return; }
      render(''); search.value = ''; popup.hidden = false; button.setAttribute('aria-expanded', 'true'); search.focus();
    };
    search.oninput = () => render(search.value);
    popup.onkeydown = event => {
      if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); close(); button.focus(); }
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        event.preventDefault(); const options = [...list.querySelectorAll('button')]; const i = options.indexOf(document.activeElement);
        options[(i + (event.key === 'ArrowDown' ? 1 : -1) + options.length) % options.length]?.focus();
      }
    };
    root.addEventListener('focusout', event => { if (!root.contains(event.relatedTarget)) close(); });
    renderButton();
    return {
      get country() { return current.iso; },
      get name() { return current.name; },
      number() {
        const value = digits(phone.value).trim();
        if (!/^[+0-9() .-]{1,32}$/.test(value)) return null;
        const parsed = lib.parsePhoneNumberFromString(value, { defaultCountry: current.iso, extract: false });
        return parsed?.isValid() && parsed.country === current.iso ? parsed.number : null;
      }
    };
  }
  window.MeemPhonePicker = { create };
})();
