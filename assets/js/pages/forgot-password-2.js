const UI = window.MeemAuthUI;
const errorBox = document.getElementById('formError');
const successBox = document.getElementById('formSuccess');
const stepBadge = document.getElementById('stepBadge');
const stepEmail = document.getElementById('stepEmail');
const stepCode = document.getElementById('stepCode');
const emailInput = document.getElementById('email');
const sendBtn = document.getElementById('sendBtn');
const verifyBtn = document.getElementById('verifyBtn');
const resendBtn = document.getElementById('resendBtn');

let targetEmail = '';

UI.bindEmailValidation(emailInput);
const otp = UI.bindOtpInputs(document.getElementById('otpBox'), () => document.getElementById('codeForm').requestSubmit());
const timer = UI.createResendTimer(resendBtn, document.getElementById('resendTimer'), 60);

function clearMessages() {
  errorBox.textContent = '';
  successBox.textContent = '';
}

async function sendCode(email) {
  const { error } = await supabaseClient.auth.resetPasswordForEmail(email);
  if (error && error.status === 429) throw new Error('rate');
  if (error) throw new Error('fail');
}

document.getElementById('emailForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  clearMessages();

  const email = emailInput.value.trim();
  if (!UI.isValidEmail(email)) {
    UI.setFieldState(emailInput, 'invalid', 'صيغة البريد غير صحيحة');
    emailInput.focus();
    return;
  }

  UI.setLoading(sendBtn, true, 'جارِ الإرسال...');
  try {
    await sendCode(email);
    targetEmail = email;
    stepEmail.hidden = true;
    stepCode.hidden = false;
    stepBadge.lastChild.textContent = ' الخطوة 2 من 3 — إدخال الكود';
    const codeSub = document.getElementById('codeSub');
    codeSub.textContent = '';
    codeSub.append('أرسلنا كودًا من 6 أرقام إلى ');
    const codeStrong = document.createElement('strong');
    codeStrong.setAttribute('dir', 'ltr');
    codeStrong.textContent = email;
    codeSub.append(codeStrong, ' — أو اضغط رابط الاستعادة في نفس الإيميل');
    successBox.textContent = 'إذا كان البريد مسجلاً لدينا فسيصلك الكود خلال لحظات';
    timer.start(60);
    otp.focus();
  } catch (err) {
    errorBox.textContent = err.message === 'rate'
      ? 'محاولات كثيرة، حاول مرة أخرى بعد قليل'
      : 'تعذر إرسال الكود الآن، حاول مرة أخرى';
  } finally {
    UI.setLoading(sendBtn, false);
  }
});

document.getElementById('codeForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  clearMessages();

  const code = otp.value();
  if (code.length !== 6) {
    errorBox.textContent = 'أدخل الكود كاملاً (6 أرقام)';
    return;
  }

  UI.setLoading(verifyBtn, true, 'جارِ التحقق...');
  try {
    const { error } = await supabaseClient.auth.verifyOtp({
      email: targetEmail,
      token: code,
      type: 'recovery'
    });

    if (error) {
      errorBox.textContent = error.status === 429
        ? 'محاولات كثيرة، حاول مرة أخرى بعد قليل'
        : 'الكود غير صحيح أو منتهي الصلاحية';
      otp.clear();
      return;
    }

    sessionStorage.setItem('recovery_email', targetEmail);
    sessionStorage.setItem('recovery_verified', '1');
    window.location.href = 'reset-password.html';
  } catch (_) {
    errorBox.textContent = 'تعذر التحقق الآن، حاول مرة أخرى';
  } finally {
    UI.setLoading(verifyBtn, false);
  }
});

resendBtn.addEventListener('click', async () => {
  clearMessages();
  timer.start(60);
  try {
    await sendCode(targetEmail);
    successBox.textContent = 'تم إرسال كود جديد إلى بريدك';
  } catch (err) {
    errorBox.textContent = err.message === 'rate'
      ? 'محاولات كثيرة، انتظر قليلاً قبل إعادة المحاولة'
      : 'تعذرت إعادة الإرسال، حاول بعد قليل';
  }
});

document.getElementById('changeEmail').addEventListener('click', (e) => {
  e.preventDefault();
  clearMessages();
  timer.stop();
  otp.clear();
  stepCode.hidden = true;
  stepEmail.hidden = false;
  stepBadge.lastChild.textContent = ' الخطوة 1 من 3 — تحديد الحساب';
  emailInput.focus();
});
