const UI = window.MeemAuthUI;
const email = sessionStorage.getItem('pending_email');
if (!email) window.location.href = 'register.html';

const subTextEl = document.getElementById('subText');
subTextEl.textContent = 'أرسلنا كودًا من 6 أرقام إلى ';
const emailStrong = document.createElement('strong');
emailStrong.dir = 'ltr';
emailStrong.textContent = email;
subTextEl.appendChild(emailStrong);

const errorBox = document.getElementById('formError');
const successBox = document.getElementById('formSuccess');
const submitBtn = document.getElementById('submitBtn');
const resendBtn = document.getElementById('resendBtn');
const form = document.getElementById('verifyForm');

const otp = UI.bindOtpInputs(document.getElementById('otpBox'), () => form.requestSubmit());
const timer = UI.createResendTimer(resendBtn, document.getElementById('resendTimer'), 60);
otp.focus();
timer.start(60);

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  if (submitBtn.disabled) return;
  errorBox.textContent = '';
  const code = otp.value();

  if (code.length !== 6) {
    errorBox.textContent = 'أدخل الكود كاملاً (6 أرقام)';
    return;
  }

  UI.setLoading(submitBtn, true, 'جارِ التحقق...');

  try {
    const { error } = await supabaseClient.auth.verifyOtp({ email, token: code, type: 'signup' });

    if (error) {
      errorBox.textContent = error.status === 429
        ? 'محاولات كثيرة، حاول مرة أخرى بعد قليل'
        : 'الكود غير صحيح أو منتهي الصلاحية';
      otp.clear();
      return;
    }

    sessionStorage.removeItem('pending_email');
    successBox.textContent = 'تم تفعيل حسابك بنجاح، جارِ فتح المتجر...';
    await window.MeemAuthFlow.finishSignIn();
  } catch (_) {
    errorBox.textContent = 'تعذر التحقق الآن، حاول مرة أخرى';
  } finally {
    UI.setLoading(submitBtn, false);
  }
});

resendBtn.addEventListener('click', async () => {
  successBox.textContent = '';
  errorBox.textContent = '';
  timer.start(60);

  try {
    const { error } = await supabaseClient.auth.resend({ type: 'signup', email });
    if (error) {
      errorBox.textContent = 'تعذرت إعادة الإرسال، حاول بعد قليل';
    } else {
      successBox.textContent = 'إذا كان الحساب بانتظار التحقق، فسيصلك كود جديد';
    }
  } catch (_) {
    errorBox.textContent = 'تعذرت إعادة الإرسال، حاول بعد قليل';
  }
});
