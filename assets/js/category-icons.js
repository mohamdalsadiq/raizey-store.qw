/* =========================================================
   MEEM STORE — smart category/section icons (shared: storefront + admin)
   Category artwork: Phosphor Duotone (local, pinned, MIT).
   Exposes window.MeemCategoryIcons and (for tests) module.exports.
   No innerHTML with DB data — callers use the returned key with the sprite.
   ========================================================= */
(function (root, factory) {
  var api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api; // unit tests
  if (root) root.MeemCategoryIcons = api;
})(typeof window !== 'undefined' ? window : null, function () {
  'use strict';

  var FALLBACK = 'layout-grid';

  // Curated category set suited to a digital-goods store. Every key here is present
  // in assets/icons/category-sprite.svg (the builder reads this list).
  var PRESETS = [
    'brain', 'gamepad-2', 'joystick', 'swords', 'crosshair', 'target', 'flame', 'zap', 'rocket',
    'crown', 'trophy', 'medal', 'gem', 'coins', 'wallet', 'banknote', 'gift', 'ticket',
    'id-card', 'credit-card', 'smartphone', 'monitor', 'tv', 'clapperboard', 'music',
    'headphones', 'app-window', 'cloud', 'download', 'layers', 'package', 'store', 'tag',
    'percent', 'sparkles', 'shield-check', 'star', 'heart', 'ghost', 'skull', 'dices',
    'puzzle', 'users', 'message-circle', 'globe', 'circle-play', 'layout-grid',
    'shopping-bag', 'shopping-cart', 'lock', 'key-round', 'wrench', 'bot', 'video', 'mic',
    'image', 'palette', 'camera', 'bell', 'clock', 'calendar', 'map-pin', 'phone', 'mail',
    'book-open', 'graduation-cap', 'plane', 'car', 'house', 'cpu', 'database', 'server',
    'terminal', 'watch', 'printer', 'wifi', 'battery-charging', 'pie-chart', 'bar-chart-3',
    'truck', 'briefcase', 'badge-check', 'piggy-bank', 'receipt', 'search', 'film', 'hash'
  ];

  // Ordered rules: first match wins. Values are stable preset keys (must exist in the sprite).
  // Each rule tests a normalized (lowercase, de-tashkeel, unified-letters) haystack.
  var RULES = [
    [/\bai\b|artificial\s*intelligence|chat\s*gpt|chatgpt|claude|gemini|midjourney|deepseek|ذكاء|شات\s*جي|جيميني/, 'brain'],
    [/توثيق|موثق|تحقق|verified|verification|blue\s*(tick|check)/, 'badge-check'],
    [/فيزا|visa|ماستر|mastercard|بطاق.*بنكي|credit\s*card|debit/, 'credit-card'],
    [/هوية|هويه|هويات|id\s*card|identity/, 'id-card'],
    [/pubg|ببجي|ببجى|بابجي/, 'crosshair'],
    [/free\s*fire|فري\s*فاير|فريفاير|freefire/, 'flame'],
    [/call\s*of\s*duty|\bcod\b|كول\s*اوف|كولوف/, 'swords'],
    [/fortnite|فورتنايت|فورت\s*نايت/, 'rocket'],
    [/roblox|روبلوكس/, 'puzzle'],
    [/minecraft|ماين\s*كرافت|ماينكرافت/, 'dices'],
    [/gta|جراند/, 'car'],
    [/fifa|فيفا/, 'trophy'],
    [/clash|كلاش/, 'crown'],
    [/عاب|العاب|ألعاب|game|gaming|games|gamer|بلايستيشن|بلاي\s*ستيشن|playstation|xbox|اكسبوكس|إكسبوكس|nintendo|نينتندو/, 'gamepad-2'],
    [/ستيم|steam|\bpc\b|كمبيوتر|حاسوب|computer/, 'monitor'],
    [/joystick|يد\s*تحكم|جويستيك/, 'joystick'],
    [/بطاق|كروت|كارد|card|gift\s*card|كارد/, 'gift'],
    [/جوجل\s*بلاي|google\s*play|جوجل/, 'circle-play'],
    [/ايتونز|آيتونز|ايتونس|itunes|ابل|آبل|apple|app\s*store/, 'smartphone'],
    [/اشتراك|اشتراكات|subscri|نتفلكس|netflix|شاهد|shahid|يوتيوب|youtube|disney/, 'clapperboard'],
    [/ديسكورد|discord/, 'message-circle'],
    [/موسيق|سبوتيفاي|spotify|music|اغاني|أغاني|اغنية/, 'music'],
    [/سماع|headphone|earbud|ايربودز|airpods/, 'headphones'],
    [/جواهر|عملات|diamond|diamonds|\bgems?\b|\buc\b|شدة|شدات|شحن\s*داخلي|جيم|جيمز/, 'gem'],
    [/محفظ|رصيد|wallet|balance|credit/, 'wallet'],
    [/تحويل|بنك|bank|banking|تحويل\s*بنكي|مصرف/, 'banknote'],
    [/كوبون|قسيم|خصم|coupon|discount|promo|voucher/, 'percent'],
    [/هداي|هدية|gift|هدايا/, 'gift'],
    [/تذك|تذاكر|ticket/, 'ticket'],
    [/فيزا|visa|ماستر|mastercard|بطاق\s*بنكي|credit\s*card|debit/, 'credit-card'],
    [/هوية|بطاقة\s*هوية|هويات|id\s*card|identity/, 'id-card'],
    [/تطبيق|تطبيقات|برام|software|apps?|application/, 'app-window'],
    [/اشتراك\s*سحابي|سحاب|cloud|icloud/, 'cloud'],
    [/تحميل|download/, 'download'],
    [/حزم|باقات|باكيج|bundle|package|pack/, 'package'],
    [/متجر|store|shop|shopping/, 'store'],
    [/وسم|تصنيف|tag|tags|label/, 'tag'],
    [/لمعان|مميز|featured|sparkle|sparkles|جديد\s*ومميز/, 'sparkles'],
    [/امان|حماي|امن|آمن|secure|security|shield|protection/, 'shield-check'],
    [/حساب\s*موثق|تحقق|verified/, 'badge-check'],
    [/نجم|مميز|star|favorite|مفضل/, 'star'],
    [/مفضل|احب|قلب|heart|favorite/, 'heart'],
    [/شبح|ghost|ghost\s*games/, 'ghost'],
    [/جمجم|skull|رعب|horror/, 'skull'],
    [/عابه|لاعب|لاعبين|players|team|فريق|مجتمع|community/, 'users'],
    [/تواصل|واتساب|whatsapp|chat|دردشة|support|دعم/, 'message-circle'],
    [/عالمي|global|globe|world|دولي/, 'globe'],
    [/تشغيل|فيديو|video|stream|بث|بثوث/, 'video'],
    [/تسجيل|صوت|mic|voice|بودكاست|podcast/, 'mic'],
    [/صور|صورة|image|photo|تصميم\s*صور/, 'image'],
    [/تصميم|palette|design|رسم/, 'palette'],
    [/كاميرا|camera/, 'camera'],
    [/اشعار|إشعار|notification|alert|تنبيه/, 'bell'],
    [/وقت|time|clock|ساعة|توقيت/, 'clock'],
    [/تقويم|calendar|مواعيد|جدول/, 'calendar'],
    [/موقع|location|map|خريطة|عنوان/, 'map-pin'],
    [/هاتف|phone|اتصال|جوال|موبايل|mobile/, 'phone'],
    [/بريد|mail|email|ايميل|إيميل/, 'mail'],
    [/كتاب|book|read|قراء|مذاكرة/, 'book-open'],
    [/تعليم|دورات|course|education|جامعة|دراسة|school/, 'graduation-cap'],
    [/سفر|طيران|flight|travel|حجز/, 'plane'],
    [/سيار|car|vehicles|مركبات/, 'car'],
    [/منزل|house|home|عقار/, 'house'],
    [/معالج|cpu|processor|chip/, 'cpu'],
    [/قواعد\s*بيانات|database/, 'database'],
    [/سيرفر|server|استضافة|hosting/, 'server'],
    [/كود|code|termux|terminal|programming|برمجة/, 'terminal'],
    [/شبكة|wifi|انترنت|إنترنت|internet/, 'wifi'],
    [/ساعات\s*ذكية|watch|ساعة\s*ذكية/, 'watch'],
    [/طباعة|print|printer/, 'printer'],
    [/شاحن|charging|بطارية|battery|power\s*bank/, 'battery-charging'],
    [/احصائ|إحصاء|إحصائيات|stats|analytics|تقارير|report/, 'bar-chart-3'],
    [/شروط|خصومات\s*نسبية|pie|نسبة/, 'pie-chart'],
    [/توصيل|شحن\s*ومنتجات|delivery|shipping|تسليم/, 'truck'],
    [/اعمال|أعمال|business|شركات|corporate/, 'briefcase'],
    [/ادخار|توفير|saving|piggy|مدخرات/, 'piggy-bank'],
    [/فواتير|فاتورة|receipt|invoice|اشعارات\s*مالية/, 'receipt'],
    [/بحث|search/, 'search'],
    [/اقفال|أقفال|امان|lock|padlock|قفل/, 'lock'],
    [/مفاتيح|key|activation|تفعيل/, 'key-round'],
    [/ادوات|أدوات|tools|tool|maintenance|صيانة/, 'wrench'],
    [/بوت|bot|مساعد|assistant|ذكاء/, 'bot'],
    [/افلام|أفلام|movies|cinema|سينما/, 'film'],
    [/رمز|qr|barcode|باركود|uuid/, 'hash'],
    [/خدمات|service|services/, 'sparkles']
  ];

  var LABELS = {
    'brain': 'ذكاء اصطناعي AI ChatGPT Claude Gemini أدوات اشتراكات',
    'bot': 'روبوت بوت مساعد', 'badge-check': 'توثيق حسابات شارة تحقق',
    'credit-card': 'فيزا ماستركارد بطاقات بنكية دفع', 'id-card': 'بطاقة هوية',
    'gamepad-2': 'ألعاب يد تحكم بلايستيشن Xbox', 'joystick': 'ألعاب عصا تحكم',
    'crosshair': 'ببجي PUBG تصويب', 'flame': 'فري فاير Free Fire نار',
    'swords': 'قتال كول أوف ديوتي سيوف', 'gift': 'بطاقات هدايا كروت',
    'wallet': 'محفظة رصيد', 'banknote': 'تحويل بنك نقود', 'coins': 'عملات',
    'gem': 'جواهر شدات', 'clapperboard': 'اشتراكات نتفلكس شاهد',
    'circle-play': 'جوجل بلاي تشغيل', 'music': 'موسيقى سبوتيفاي',
    'app-window': 'تطبيقات برامج', 'shield-check': 'أمان حماية',
    'cloud': 'سحابة تخزين', 'key-round': 'مفاتيح تفعيل تراخيص',
    'globe': 'عالمي إنترنت', 'message-circle': 'دردشة تواصل واتساب ديسكورد',
    'headphones': 'سماعات صوت', 'smartphone': 'هاتف آيفون آبل',
    'monitor': 'كمبيوتر ستيم', 'tv': 'تلفزيون بث', 'video': 'فيديو تصوير',
    'image': 'صور', 'palette': 'تصميم رسم', 'camera': 'كاميرا',
    'sparkles': 'خدمات مميزة', 'package': 'باقات حزم', 'store': 'متجر',
    'ticket': 'تذاكر قسائم', 'percent': 'عروض خصومات كوبونات',
    'crown': 'تاج كلاش', 'trophy': 'بطولة فيفا', 'rocket': 'فورتنايت صاروخ',
    'puzzle': 'روبلوكس ألغاز', 'dices': 'ماينكرافت مكعبات',
    'cpu': 'معالج', 'database': 'قاعدة بيانات', 'server': 'استضافة خادم',
    'terminal': 'برمجة كود', 'book-open': 'كتب قراءة', 'graduation-cap': 'تعليم دورات',
    'receipt': 'فواتير', 'hash': 'رمز QR باركود', 'layout-grid': 'أقسام تصنيفات'
  };
  function label(key) { return LABELS[key] || key; }
  function matches(key, query) {
    var q = normalize(query);
    var text = normalize(key + ' ' + label(key));
    var literalMatch = /^[a-z0-9]{1,2}$/.test(q) ? text.split(' ').includes(q) : text.includes(q);
    return !q || literalMatch || suggest(q, '__none__') === key;
  }
  function createIcon(key) {
    var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('class', 'mm-category-icon');
    svg.setAttribute('viewBox', '0 0 256 256');
    svg.setAttribute('aria-hidden', 'true');
    svg.setAttribute('focusable', 'false');
    var use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
    use.setAttribute('href', 'assets/icons/category-sprite.svg#i-' + (isValidKey(key) ? key : FALLBACK));
    svg.appendChild(use);
    return svg;
  }

  // Arabic normalization: strip tashkeel/tatweel, unify alef/yaa/taa-marbuta.
  function normalize(value) {
    if (value == null) return '';
    var s = String(value).toLowerCase();
    s = s.replace(/[\u0617-\u061A\u064B-\u0652\u0670\u0640]/g, ''); // diacritics + tatweel
    s = s.replace(/[أإآٱ]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه').replace(/ؤ/g, 'و').replace(/ئ/g, 'ي');
    s = s.replace(/[^\p{L}\p{N}\s]/gu, ' '); // punctuation → space
    return s.replace(/\s+/g, ' ').trim();
  }

  function suggest(name, fallback) {
    var hay = normalize(name);
    if (!hay) return fallback || FALLBACK;
    for (var i = 0; i < RULES.length; i++) {
      if (RULES[i][0].test(hay)) return RULES[i][1];
    }
    return fallback || FALLBACK;
  }

  function isValidKey(key) {
    return typeof key === 'string' && /^[a-z0-9-]{2,40}$/.test(key) && PRESETS.indexOf(key) >= 0;
  }

  /* Resolve the icon key for one row given its icon columns:
       icon_mode = custom → caller must render icon_image_url with <img>
       icon_mode = preset → validated icon_key
       icon_mode = auto   → smart suggestion from `name`
       (anything else / missing) → auto, so it works before the migration lands */
  function resolve(row) {
    row = row || {};
    var mode = String(row.icon_mode || '').trim();
    var key = String(row.icon_key || '').trim();
    if (mode === 'custom') return { mode: 'custom', image: row.icon_image_url || '', key: suggest(row.name) };
    if (mode === 'preset' && isValidKey(key)) return { mode: 'preset', key: key, image: '' };
    return { mode: 'auto', key: suggest(row.name), image: '' };
  }

  return {
    createIcon: createIcon,
    label: label,
    matches: matches,
    FALLBACK: FALLBACK,
    PRESETS: PRESETS.slice(),
    normalize: normalize,
    suggest: suggest,
    isValidKey: isValidKey,
    resolve: resolve
  };
});
