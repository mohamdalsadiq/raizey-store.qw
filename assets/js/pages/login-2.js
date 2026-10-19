const UI = window.MeemAuthUI;
const form = document.getElementById('loginForm');
const errorBox = document.getElementById('formError');
const submitBtn = document.getElementById('submitBtn');
const emailInput = document.getElementById('email');
const passwordInput = document.getElementById('password');
const otpModeBtn = document.getElementById('otpModeBtn');
const otpLoginPanel = document.getElementById('otpLoginPanel');
const otpVerifyBtn = document.getElementById('otpVerifyBtn');
const otpResendBtn = document.getElementById('otpResendBtn');
const otpCodeSub = document.getElementById('otpCodeSub');
const otpTimer = UI.createResendTimer(otpResendBtn, document.getElementById('otpResendTimer'), 60);
const loginOtp = UI.bindOtpInputs(document.getElementById('loginOtpBox'), () => document.getElementById('otpLoginForm').requestSubmit());
let otpTargetEmail = '';

UI.bindPasswordToggles();
UI.bindEmailValidation(emailInput);

async function redirectAfterLogin() { await window.MeemAuthFlow.finishSignIn(); }

function clearMessages() {
  errorBox.textContent = '';
}

function resetOtpMode() {
  otpTimer.stop();
  loginOtp.clear();
  otpTargetEmail = '';
  otpLoginPanel.hidden = true;
  form.hidden = false;
  otpModeBtn.hidden = false;
  emailInput.focus();
}

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  if (e.submitter?.disabled) return;
  clearMessages();

  const email = emailInput.value.trim();
  const password = passwordInput.value;

  if (!UI.isValidEmail(email)) {
    UI.setFieldState(emailInput, 'invalid', 'أدخل بريدًا إلكترونيًا صالحًا');
    emailInput.focus();
    return;
  }
  if (!password) {
    UI.setFieldState(passwordInput, 'invalid', 'أدخل كلمة السر');
    passwordInput.focus();
    return;
  }

  UI.setLoading(submitBtn, true, 'جارِ الدخول...');

  try {
    const { error } = await supabaseClient.auth.signInWithPassword({ email, password });

    if (error) {
      if (error.message.includes('Email not confirmed')) {
        sessionStorage.setItem('pending_email', email);
        window.location.href = 'verify.html';
        return;
      }
      errorBox.textContent = error.status === 429
        ? 'محاولات كثيرة، حاول مرة أخرى بعد قليل'
        : 'الإيميل أو كلمة السر غير صحيحة';
      return;
    }
    await redirectAfterLogin();
  } catch (_) {
    errorBox.textContent = 'تعذر تسجيل الدخول الآن، حاول مرة أخرى';
  } finally {
    UI.setLoading(submitBtn, false);
  }
});

/* الدخول بـ OTP لا ينشئ حسابات — المستخدم يجب أن يكون مسجلاً مسبقاً (المهمة 5) */
function isNoAccountError(err) {
  const msg = String((err && (err.message || err.msg)) || '').toLowerCase();
  const code = String((err && (err.code || err.error_code)) || '').toLowerCase();
  return /user not found|not found|no user|user_not_found/.test(msg + ' ' + code)
    || err?.status === 400 || err?.status === 404 || err?.status === 422;
}

otpModeBtn.addEventListener('click', async () => {
  clearMessages();
  const email = emailInput.value.trim();
  if (!UI.isValidEmail(email)) {
    UI.setFieldState(emailInput, 'invalid', 'أدخل بريدًا إلكترونيًا صالحًا أولاً');
    emailInput.focus();
    return;
  }

  UI.setLoading(otpModeBtn, true, 'جارِ إرسال الكود...');
  try {
    const { error } = await supabaseClient.auth.signInWithOtp({
      email,
      options: { shouldCreateUser: false }
    });
    if (error) throw error;
    otpTargetEmail = email;
    otpCodeSub.textContent = 'إذا كان هذا البريد مسجلاً لدينا، أرسلنا إليه كودًا من 6 أرقام.';
    form.hidden = true;
    otpModeBtn.hidden = true;
    otpLoginPanel.hidden = false;
    otpTimer.start(60);
    loginOtp.focus();
  } catch (err) {
    if (err && err.status === 429) {
      errorBox.textContent = 'محاولات كثيرة، حاول مرة أخرى بعد قليل';
    } else if (isNoAccountError(err)) {
      // P2-AUTH-001: لا نكشف وجود الحساب — نفس رسالة النجاح المحايدة.
      // لوحة الكود تظهر أيضاً؛ التحقق سيفشل بشكل طبيعي لبريد غير مسجل.
      otpTargetEmail = email;
      otpCodeSub.textContent = 'إذا كان هذا البريد مسجلاً لدينا، أرسلنا إليه كودًا من 6 أرقام.';
      form.hidden = true;
      otpModeBtn.hidden = true;
      otpLoginPanel.hidden = false;
      otpTimer.start(60);
      loginOtp.focus();
    } else {
      errorBox.textContent = 'تعذر إرسال كود الدخول الآن، حاول مرة أخرى';
    }
  } finally {
    UI.setLoading(otpModeBtn, false);
  }
});

document.getElementById('otpLoginForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  if (e.submitter?.disabled) return;
  clearMessages();
  const code = loginOtp.value();
  if (code.length !== 6) {
    errorBox.textContent = 'أدخل الكود كاملاً (6 أرقام)';
    return;
  }

  UI.setLoading(otpVerifyBtn, true, 'جارِ التحقق...');
  try {
    const { error } = await supabaseClient.auth.verifyOtp({
      email: otpTargetEmail,
      token: code,
      type: 'email'
    });
    if (error) {
      errorBox.textContent = error.status === 429
        ? 'محاولات كثيرة، حاول مرة أخرى بعد قليل'
        : 'الكود غير صحيح أو منتهي الصلاحية';
      loginOtp.clear();
      return;
    }
    await redirectAfterLogin();
  } catch (_) {
    errorBox.textContent = 'تعذر التحقق الآن، حاول مرة أخرى';
  } finally {
    UI.setLoading(otpVerifyBtn, false);
  }
});

otpResendBtn.addEventListener('click', async () => {
  clearMessages();
  otpTimer.start(60);
  try {
    const { error } = await supabaseClient.auth.signInWithOtp({
      email: otpTargetEmail,
      options: { shouldCreateUser: false }
    });
    if (error && !isNoAccountError(error)) throw error;
  } catch (err) {
    errorBox.textContent = err && err.status === 429
      ? 'محاولات كثيرة، انتظر قليلاً قبل إعادة المحاولة'
      : 'تعذرت إعادة إرسال الكود، حاول بعد قليل';
  }
});

document.getElementById('changeOtpEmail').addEventListener('click', () => {
  clearMessages();
  resetOtpMode();
});

document.getElementById('backToPassword').addEventListener('click', () => {
  clearMessages();
  resetOtpMode();
});

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
    socialError.textContent = 'تعذر بدء تسجيل الدخول بجوجل، حاول مرة أخرى';
    UI.setLoading(googleBtn, false);
  }
});
