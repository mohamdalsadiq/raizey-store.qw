const UI = window.MeemAuthUI;
const form = document.getElementById('registerForm');
const errorBox = document.getElementById('formError');
const submitBtn = document.getElementById('submitBtn');

const fullNameInput = document.getElementById('fullName');
const emailInput = document.getElementById('email');
const phoneInput = document.getElementById('whatsapp');
const passwordInput = document.getElementById('password');
const confirmInput = document.getElementById('confirmPassword');
const policyInput = document.getElementById('acceptPolicy');
const referralCodeInput = document.getElementById('referralCode');
let referralValidationTimer = null;

UI.bindPasswordToggles();
UI.bindEmailValidation(emailInput);
UI.bindPasswordStrength(
  passwordInput,
  document.getElementById('pwStrengthFill'),
  document.getElementById('pwStrengthLabel'),
  document.getElementById('pwRules')
);
UI.bindConfirmPassword(passwordInput, confirmInput);

fullNameInput.addEventListener('input', () => {
  const v = fullNameInput.value.trim();
  if (!v) return UI.setFieldState(fullNameInput, null, '');
  v.length >= 3
    ? UI.setFieldState(fullNameInput, 'valid', '')
    : UI.setFieldState(fullNameInput, 'invalid', 'الاسم قصير جداً');
});

const picker = window.MeemCountries.createCountryPicker({
  root: document.getElementById('countrySelect'),
  button: document.getElementById('countryBtn'),
  popup: document.getElementById('countryPop'),
  searchInput: document.getElementById('countrySearch'),
  listBox: document.getElementById('countryList'),
  input: phoneInput,
  onChange: validatePhone
});

function validatePhone() {
  const raw = phoneInput.value.replace(/\D/g, '');
  phoneInput.value = raw;
  if (!raw) { UI.setFieldState(phoneInput, null, ''); return false; }
  if (picker.isValid(raw)) {
    UI.setFieldState(phoneInput, 'valid', 'رقم صحيح: ' + picker.fullNumber(raw));
    return true;
  }
  const lens = picker.country.len.join(' أو ');
  UI.setFieldState(phoneInput, 'invalid', 'رقم ' + picker.country.ar + ' يجب أن يكون ' + lens + ' أرقام بدون صفر في البداية');
  return false;
}
phoneInput.addEventListener('input', validatePhone);
phoneInput.addEventListener('blur', validatePhone);

async function validateReferralCode(showMessage = true) {
  const code = referralCodeInput.value.trim().toUpperCase();
  referralCodeInput.value = code;
  if (!code) {
    UI.setFieldState(referralCodeInput, null, 'يمكنك كتابة الكود القصير أو استخدام رابط الإحالة.');
    return true;
  }
  if (!/^[A-Z0-9]{5,32}$/.test(code)) {
    UI.setFieldState(referralCodeInput, 'invalid', 'اكتب كود الإحالة كما استلمته، من 5 خانات فأكثر.');
    return false;
  }
  const { data, error } = await supabaseClient.rpc('validate_referral_short_code', { p_code: code });
  const row = Array.isArray(data) ? data[0] : data;
  if (error || !row || row.valid !== true) {
    const reason = row?.reason;
    const message = reason === 'self_referral'
      ? 'لا يمكنك استخدام كود الإحالة الخاص بك.'
      : 'كود الإحالة غير موجود أو غير صالح.';
    UI.setFieldState(referralCodeInput, 'invalid', showMessage ? message : 'الكود غير صالح');
    return false;
  }
  UI.setFieldState(referralCodeInput, 'valid', 'كود إحالة صالح وسيُحتسب عند إنشاء الحساب.');
  return true;
}

referralCodeInput.addEventListener('input', () => {
  clearTimeout(referralValidationTimer);
  if (!referralCodeInput.value.trim()) { validateReferralCode(false); return; }
  referralValidationTimer = setTimeout(() => validateReferralCode(false), 450);
});
referralCodeInput.addEventListener('blur', () => validateReferralCode(true));

const referralFromUrl = new URLSearchParams(window.location.search).get('ref');
if (referralFromUrl) {
  referralCodeInput.value = referralFromUrl.trim().toUpperCase().slice(0, 32);
  validateReferralCode(false);
}

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  errorBox.textContent = '';

  const fullName = fullNameInput.value.trim();
  const email = emailInput.value.trim();
  const password = passwordInput.value;
  const confirmPassword = confirmInput.value;
  const referralCode = referralCodeInput.value.trim().toUpperCase();

  if (fullName.length < 3) {
    errorBox.textContent = 'اكتب اسمك الكامل بشكل صحيح';
    fullNameInput.focus();
    return;
  }
  if (!UI.isValidEmail(email)) {
    UI.setFieldState(emailInput, 'invalid', 'صيغة البريد غير صحيحة');
    errorBox.textContent = 'أدخل بريدًا إلكترونيًا صالحًا — سيصلك عليه كود التفعيل';
    emailInput.focus();
    return;
  }
  if (!validatePhone()) {
    errorBox.textContent = 'أدخل رقم واتساب صحيح حسب الدولة المختارة';
    phoneInput.focus();
    return;
  }
  if (password.length < 8 || !/[A-Za-z]/.test(password) || !/[0-9]/.test(password)) {
    errorBox.textContent = 'كلمة السر لازم تكون 8 أحرف على الأقل وتحتوي على حرف ورقم';
    passwordInput.focus();
    return;
  }
  if (password !== confirmPassword) {
    errorBox.textContent = 'كلمة السر غير متطابقة';
    confirmInput.focus();
    return;
  }
  if (!policyInput.checked) {
    errorBox.textContent = 'يجب الموافقة على سياسة الخصوصية وشروط الاستخدام للمتابعة';
    policyInput.focus();
    return;
  }
  if (referralCode && !(await validateReferralCode(true))) {
    errorBox.textContent = 'تحقق من كود الإحالة قبل إنشاء الحساب';
    referralCodeInput.focus();
    return;
  }

  UI.setLoading(submitBtn, true, 'جارِ الإنشاء...');

  try {
    const { error } = await supabaseClient.auth.signUp({
      email,
      password,
      options: {
        data: {
          full_name: fullName.slice(0, 120),
          whatsapp_number: picker.fullNumber(phoneInput.value),
          whatsapp_country: picker.country.iso.toUpperCase(),
          referral_code_used: referralCode || null
        }
      }
    });

    if (error) {
      errorBox.textContent = translateError(error);
      return;
    }

    sessionStorage.setItem('pending_email', email);
    window.location.href = 'verify.html';
  } catch (_) {
    errorBox.textContent = 'تعذر إنشاء الحساب الآن، حاول مرة أخرى';
  } finally {
    UI.setLoading(submitBtn, false);
  }
});

function translateError(error) {
  if (error.status === 429 || error.message.includes('rate limit')) {
    return 'محاولات كثيرة، حاول مرة أخرى بعد قليل';
  }
  if (error.message.toLowerCase().includes('password')) {
    return 'كلمة السر لا تستوفي متطلبات الأمان';
  }
  return 'تعذر إنشاء الحساب بهذه البيانات، تحقق منها أو سجّل الدخول';
}

document.getElementById('googleLoginBtn').addEventListener('click', async () => {
  const googleBtn = document.getElementById('googleLoginBtn');
  const socialError = document.getElementById('socialError');
  socialError.textContent = '';
  UI.setLoading(googleBtn, true, 'جارِ التحويل إلى جوجل...');

  try {
    const { error } = await supabaseClient.auth.signInWithOAuth({
      provider: 'google',
      options: {
        redirectTo: new URL('index.html', window.location.href).href,
        queryParams: { prompt: 'select_account' }
      }
    });
    if (error) throw error;
  } catch (_) {
    socialError.textContent = 'تعذر بدء التسجيل بجوجل، حاول مرة أخرى';
    UI.setLoading(googleBtn, false);
  }
});
