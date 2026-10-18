const UI = window.MeemAuthUI;
const errorBox = document.getElementById('formError');
const successBox = document.getElementById('formSuccess');
const submitBtn = document.getElementById('submitBtn');
const passwordInput = document.getElementById('password');
const confirmInput = document.getElementById('confirmPassword');
const form = document.getElementById('resetForm');

UI.bindPasswordToggles();
UI.bindPasswordStrength(
  passwordInput,
  document.getElementById('pwStrengthFill'),
  document.getElementById('pwStrengthLabel'),
  document.getElementById('pwRules')
);
UI.bindConfirmPassword(passwordInput, confirmInput);

const recoveryEmail = sessionStorage.getItem('recovery_email');
if (recoveryEmail) {
  const subTextEl = document.getElementById('subText');
  subTextEl.textContent = '';
  subTextEl.append('تم التحقق من ');
  const strongEl = document.createElement('strong');
  strongEl.setAttribute('dir', 'ltr');
  strongEl.textContent = recoveryEmail;
  subTextEl.append(strongEl, ' — اختر كلمة سر جديدة');
}

/* التأكد من وجود جلسة استعادة صالحة.
   تبادل كود رابط الاستعادة (PKCE) يتم بشكل غير متزامن عند تحميل الصفحة،
   فنعيد المحاولة بضع ثوانٍ قبل الحكم بانتهاء الجلسة. */
(async function guard() {
  let session = null;
  for (let i = 0; i < 12; i++) {
    try {
      const { data } = await supabaseClient.auth.getSession();
      if (data && data.session) { session = data.session; break; }
    } catch (_) { /* حاول مجدداً */ }
    await new Promise((r) => setTimeout(r, 300));
  }
  if (!session) {
    form.querySelectorAll('input, button').forEach((el) => { el.disabled = true; });
    errorBox.textContent = 'انتهت صلاحية جلسة الاستعادة، اطلب كودًا جديدًا';
    setTimeout(() => { window.location.href = 'forgot-password.html'; }, 2200);
  }
})();

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  errorBox.textContent = '';
  successBox.textContent = '';

  const password = passwordInput.value;
  const confirmPassword = confirmInput.value;

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

  UI.setLoading(submitBtn, true, 'جارِ الحفظ...');

  try {
    const { error } = await supabaseClient.auth.updateUser({ password });

    if (error) {
      errorBox.textContent = error.status === 429
        ? 'محاولات كثيرة، حاول مرة أخرى بعد قليل'
        : 'تعذر تحديث كلمة السر، اطلب كودًا جديدًا وحاول مرة أخرى';
      return;
    }

    sessionStorage.removeItem('recovery_email');
    sessionStorage.removeItem('recovery_verified');
    successBox.textContent = 'تم تحديث كلمة السر بنجاح، جارِ فتح المتجر...';
    setTimeout(() => { window.location.href = 'index.html'; }, 900);
  } catch (_) {
    errorBox.textContent = 'تعذر تحديث كلمة السر الآن، حاول مرة أخرى';
  } finally {
    UI.setLoading(submitBtn, false);
  }
});
