/* =========================================================
   RAIZEY STORE — بيانات الدول ومنطق منتقي رمز الدولة
   الافتراضي: السودان (+249)
   ========================================================= */
(function (global) {
  'use strict';

  // len: الأطوال المسموحة للرقم الوطني (بدون رمز الدولة)
  var COUNTRIES = [
    { iso: 'sd', ar: 'السودان',            en: 'Sudan',                dial: '249', len: [9] },
    { iso: 'sa', ar: 'السعودية',           en: 'Saudi Arabia',         dial: '966', len: [9] },
    { iso: 'ae', ar: 'الإمارات',           en: 'United Arab Emirates', dial: '971', len: [9] },
    { iso: 'eg', ar: 'مصر',                en: 'Egypt',                dial: '20',  len: [10] },
    { iso: 'qa', ar: 'قطر',                en: 'Qatar',                dial: '974', len: [8] },
    { iso: 'kw', ar: 'الكويت',             en: 'Kuwait',               dial: '965', len: [8] },
    { iso: 'bh', ar: 'البحرين',            en: 'Bahrain',              dial: '973', len: [8] },
    { iso: 'om', ar: 'عُمان',              en: 'Oman',                 dial: '968', len: [8] },
    { iso: 'jo', ar: 'الأردن',             en: 'Jordan',               dial: '962', len: [9] },
    { iso: 'ly', ar: 'ليبيا',              en: 'Libya',                dial: '218', len: [9] },
    { iso: 'tn', ar: 'تونس',               en: 'Tunisia',              dial: '216', len: [8] },
    { iso: 'dz', ar: 'الجزائر',            en: 'Algeria',              dial: '213', len: [9] },
    { iso: 'ma', ar: 'المغرب',             en: 'Morocco',              dial: '212', len: [9] },
    { iso: 'mr', ar: 'موريتانيا',          en: 'Mauritania',           dial: '222', len: [8] },
    { iso: 'ye', ar: 'اليمن',              en: 'Yemen',                dial: '967', len: [9] },
    { iso: 'iq', ar: 'العراق',             en: 'Iraq',                 dial: '964', len: [10] },
    { iso: 'sy', ar: 'سوريا',              en: 'Syria',                dial: '963', len: [9] },
    { iso: 'lb', ar: 'لبنان',              en: 'Lebanon',              dial: '961', len: [7, 8] },
    { iso: 'ps', ar: 'فلسطين',             en: 'Palestine',            dial: '970', len: [9] },
    { iso: 'so', ar: 'الصومال',            en: 'Somalia',              dial: '252', len: [7, 8, 9] },
    { iso: 'dj', ar: 'جيبوتي',             en: 'Djibouti',             dial: '253', len: [8] },
    { iso: 'km', ar: 'جزر القمر',          en: 'Comoros',              dial: '269', len: [7] },
    { iso: 'ss', ar: 'جنوب السودان',       en: 'South Sudan',          dial: '211', len: [9] },
    { iso: 'et', ar: 'إثيوبيا',            en: 'Ethiopia',             dial: '251', len: [9] },
    { iso: 'er', ar: 'إريتريا',            en: 'Eritrea',              dial: '291', len: [7] },
    { iso: 'ke', ar: 'كينيا',              en: 'Kenya',                dial: '254', len: [9] },
    { iso: 'ug', ar: 'أوغندا',             en: 'Uganda',               dial: '256', len: [9] },
    { iso: 'tz', ar: 'تنزانيا',            en: 'Tanzania',             dial: '255', len: [9] },
    { iso: 'td', ar: 'تشاد',               en: 'Chad',                 dial: '235', len: [8] },
    { iso: 'ng', ar: 'نيجيريا',            en: 'Nigeria',              dial: '234', len: [10] },
    { iso: 'gh', ar: 'غانا',               en: 'Ghana',                dial: '233', len: [9] },
    { iso: 'za', ar: 'جنوب أفريقيا',       en: 'South Africa',         dial: '27',  len: [9] },
    { iso: 'tr', ar: 'تركيا',              en: 'Turkey',               dial: '90',  len: [10] },
    { iso: 'ir', ar: 'إيران',              en: 'Iran',                 dial: '98',  len: [10] },
    { iso: 'pk', ar: 'باكستان',            en: 'Pakistan',             dial: '92',  len: [10] },
    { iso: 'in', ar: 'الهند',              en: 'India',                dial: '91',  len: [10] },
    { iso: 'bd', ar: 'بنغلاديش',           en: 'Bangladesh',           dial: '880', len: [10] },
    { iso: 'id', ar: 'إندونيسيا',          en: 'Indonesia',            dial: '62',  len: [9, 10, 11] },
    { iso: 'my', ar: 'ماليزيا',            en: 'Malaysia',             dial: '60',  len: [9, 10] },
    { iso: 'ph', ar: 'الفلبين',            en: 'Philippines',          dial: '63',  len: [10] },
    { iso: 'cn', ar: 'الصين',              en: 'China',                dial: '86',  len: [11] },
    { iso: 'jp', ar: 'اليابان',            en: 'Japan',                dial: '81',  len: [10] },
    { iso: 'kr', ar: 'كوريا الجنوبية',     en: 'South Korea',          dial: '82',  len: [9, 10] },
    { iso: 'gb', ar: 'بريطانيا',           en: 'United Kingdom',       dial: '44',  len: [10] },
    { iso: 'us', ar: 'الولايات المتحدة',   en: 'United States',        dial: '1',   len: [10] },
    { iso: 'ca', ar: 'كندا',               en: 'Canada',               dial: '1',   len: [10] },
    { iso: 'de', ar: 'ألمانيا',            en: 'Germany',              dial: '49',  len: [10, 11] },
    { iso: 'fr', ar: 'فرنسا',              en: 'France',               dial: '33',  len: [9] },
    { iso: 'it', ar: 'إيطاليا',            en: 'Italy',                dial: '39',  len: [9, 10] },
    { iso: 'es', ar: 'إسبانيا',            en: 'Spain',                dial: '34',  len: [9] },
    { iso: 'nl', ar: 'هولندا',             en: 'Netherlands',          dial: '31',  len: [9] },
    { iso: 'se', ar: 'السويد',             en: 'Sweden',               dial: '46',  len: [9] },
    { iso: 'no', ar: 'النرويج',            en: 'Norway',               dial: '47',  len: [8] },
    { iso: 'dk', ar: 'الدنمارك',           en: 'Denmark',              dial: '45',  len: [8] },
    { iso: 'be', ar: 'بلجيكا',             en: 'Belgium',              dial: '32',  len: [9] },
    { iso: 'ch', ar: 'سويسرا',             en: 'Switzerland',          dial: '41',  len: [9] },
    { iso: 'at', ar: 'النمسا',             en: 'Austria',              dial: '43',  len: [10] },
    { iso: 'ru', ar: 'روسيا',              en: 'Russia',               dial: '7',   len: [10] },
    { iso: 'ua', ar: 'أوكرانيا',           en: 'Ukraine',              dial: '380', len: [9] },
    { iso: 'au', ar: 'أستراليا',           en: 'Australia',            dial: '61',  len: [9] },
    { iso: 'br', ar: 'البرازيل',           en: 'Brazil',               dial: '55',  len: [10, 11] }
  ];

  function flagUrl(iso) {
    return 'https://flagcdn.com/w40/' + iso + '.png';
  }

  function maxLen(country) {
    return Math.max.apply(null, country.len);
  }

  function isValidNumber(country, national) {
    var digits = String(national || '').replace(/\D/g, '');
    if (!digits) return false;
    if (digits.charAt(0) === '0') return false;
    return country.len.indexOf(digits.length) !== -1;
  }

  /**
   * إنشاء منتقي الدولة داخل حاوية الحقل.
   * options: { root, button, popup, searchInput, listBox, input, onChange }
   */
  function createCountryPicker(options) {
    var root = options.root;
    var button = options.button;
    var popup = options.popup;
    var search = options.searchInput;
    var list = options.listBox;
    var phoneInput = options.input;
    var current = COUNTRIES[0];

    function renderButton() {
      button.innerHTML =
        '<img class="flag" src="' + flagUrl(current.iso) + '" alt="' + current.ar + '" loading="lazy">' +
        '<span class="dial">+' + current.dial + '</span>' +
        '<svg class="chev" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9l6 6 6-6"/></svg>';
      phoneInput.setAttribute('maxlength', String(maxLen(current)));
      phoneInput.setAttribute('placeholder', new Array(maxLen(current) + 1).join('X'));
    }

    function renderList(query) {
      var q = (query || '').trim().toLowerCase().replace(/^\+/, '');
      var items = COUNTRIES.filter(function (c) {
        if (!q) return true;
        return c.ar.indexOf(q) !== -1 ||
          c.en.toLowerCase().indexOf(q) !== -1 ||
          c.dial.indexOf(q) === 0 ||
          c.iso === q;
      });

      if (!items.length) {
        list.innerHTML = '<div class="country-empty">لا توجد نتائج مطابقة</div>';
        return;
      }

      list.innerHTML = items.map(function (c) {
        return '<button type="button" class="country-item' + (c.iso === current.iso ? ' active' : '') +
          '" data-iso="' + c.iso + '" data-dial="' + c.dial + '">' +
          '<img class="flag" src="' + flagUrl(c.iso) + '" alt="" loading="lazy">' +
          '<span class="nm">' + c.ar + '</span>' +
          '<span class="dial">+' + c.dial + '</span></button>';
      }).join('');
    }

    function open() {
      renderList('');
      search.value = '';
      popup.classList.add('open');
      button.setAttribute('aria-expanded', 'true');
      setTimeout(function () { search.focus(); }, 30);
    }

    function close() {
      popup.classList.remove('open');
      button.setAttribute('aria-expanded', 'false');
    }

    button.addEventListener('click', function () {
      popup.classList.contains('open') ? close() : open();
    });

    search.addEventListener('input', function () { renderList(search.value); });

    list.addEventListener('click', function (e) {
      var item = e.target.closest('.country-item');
      if (!item) return;
      var iso = item.dataset.iso;
      var dial = item.dataset.dial;
      current = COUNTRIES.filter(function (c) { return c.iso === iso && c.dial === dial; })[0] || current;
      renderButton();
      close();
      phoneInput.focus();
      if (typeof options.onChange === 'function') options.onChange(current);
    });

    document.addEventListener('click', function (e) {
      if (!root.contains(e.target)) close();
    });

    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') close();
    });

    renderButton();

    return {
      get country() { return current; },
      isValid: function (value) { return isValidNumber(current, value); },
      fullNumber: function (value) {
        return '+' + current.dial + String(value || '').replace(/\D/g, '');
      }
    };
  }

  global.RaizeyCountries = {
    list: COUNTRIES,
    flagUrl: flagUrl,
    isValidNumber: isValidNumber,
    createCountryPicker: createCountryPicker
  };
})(window);
