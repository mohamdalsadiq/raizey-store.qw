const UI = window.MeemAuthUI;
let currentUser = null;
let currentProfile = null;
let avatarPath = '';
let pendingPasswordNonce = '';
let reauthEmail = '';
let reauthMode = 'session';
let reauthResolver = null;
let pendingMfaFactor = null;

const formError = document.getElementById('formError');
const formSuccess = document.getElementById('formSuccess');
const securityError = document.getElementById('securityError');
const securitySuccess = document.getElementById('securitySuccess');
const avatarInput = document.getElementById('avatarFileInput');
const avatarStatus = document.getElementById('avatarStatus');
const emailInput = document.getElementById('emailInput');
const pendingBadge = document.getElementById('pendingBadge');
const verifiedBadge = document.getElementById('verifiedBadge');
const resendConfirmBtn = document.getElementById('resendConfirmBtn');
const saveBtn = document.getElementById('saveBtn');
const playerIdList = document.getElementById('playerIdList');
const currencySelect = document.getElementById('currencySelect');
const reauthModal = document.getElementById('reauthModal');
const reauthSub = document.getElementById('reauthSub');
const reauthError = document.getElementById('reauthError');
const reauthVerifyBtn = document.getElementById('reauthVerifyBtn');
const reauthResendBtn = document.getElementById('reauthResendBtn');
const reauthOtp = UI.bindOtpInputs(document.getElementById('reauthOtpBox'), () => document.getElementById('reauthForm').requestSubmit());
const reauthTimer = UI.createResendTimer(reauthResendBtn, document.getElementById('reauthResendTimer'), 60);

UI.bindPasswordToggles();
UI.bindPasswordStrength(document.getElementById('newPasswordInput'), document.getElementById('pwStrengthFill'), document.getElementById('pwStrengthLabel'), document.getElementById('pwRules'));
UI.bindConfirmPassword(document.getElementById('newPasswordInput'), document.getElementById('confirmPasswordInput'));

// ---------- القائمة المنسدلة: قسم واحد مفتوح في كل مرة ----------
const accHeads = document.querySelectorAll('[data-acc]');
accHeads.forEach((head) => {
  head.addEventListener('click', () => {
    const item = head.closest('.acc-item');
    const willOpen = !item.classList.contains('open');
    document.querySelectorAll('.acc-item.open').forEach((el) => {
      el.classList.remove('open');
      const h = el.querySelector('[data-acc]');
      if (h) h.setAttribute('aria-expanded', 'false');
    });
    if (willOpen) {
      item.classList.add('open');
      head.setAttribute('aria-expanded', 'true');
      window.requestAnimationFrame(() => item.scrollIntoView({ behavior: 'smooth', block: 'start' }));
    }
  });
});
function openFromHash() {
  const key = (location.hash || '').replace('#', '');
  if (!key) return;
  const target = document.getElementById('acc-' + key) || document.getElementById(key);
  const head = target && target.matches('.acc-item') ? target.querySelector('[data-acc]') : null;
  if (head && !target.classList.contains('open')) head.click();
}
window.addEventListener('hashchange', openFromHash);

function clearMessages() { formError.textContent = ''; formSuccess.textContent = ''; }
function clearSecurityMessages() { securityError.textContent = ''; securitySuccess.textContent = ''; }

function closeReauth(result) {
  reauthTimer.stop();
  reauthOtp.clear();
  reauthModal.hidden = true;
  const resolver = reauthResolver;
  reauthResolver = null;
  if (resolver) resolver(result);
}

async function sendReauthCode() {
  reauthError.textContent = '';
  const response = reauthMode === 'password'
    ? await supabaseClient.auth.reauthenticate()
    : await supabaseClient.auth.signInWithOtp({ email: reauthEmail });
  if (response.error) throw response.error;
  reauthTimer.start(60);
  reauthOtp.focus();
}

function requestReauthentication(reason, mode) {
  if (!currentUser || !currentUser.email) return Promise.resolve(false);
  if (reauthResolver) closeReauth(false);
  reauthEmail = currentUser.email;
  reauthMode = mode || 'session';
  reauthSub.textContent = 'للمتابعة في ' + reason + '، أرسلنا كودًا من 6 أرقام إلى بريدك الحالي ' + reauthEmail + '.';
  reauthError.textContent = '';
  reauthModal.hidden = false;
  const promise = new Promise((resolve) => { reauthResolver = resolve; });
  sendReauthCode().catch((error) => {
    reauthError.textContent = error && error.status === 429 ? 'محاولات كثيرة، انتظر قليلاً قبل طلب كود جديد.' : 'تعذر إرسال كود تأكيد الهوية الآن. حاول مرة أخرى.';
    closeReauth(false);
  });
  return promise;
}

function renderPlayerIds(playerIds) {
  playerIdList.innerHTML = '';
  const entries = Object.entries(playerIds || {});
  (entries.length ? entries : [['pubg', '']]).forEach(([game, value]) => addPlayerIdRow(game, value));
}

function addPlayerIdRow(game, value) {
  const row = document.createElement('div');
  row.className = 'player-id-row';
  row.innerHTML = '<select aria-label="اللعبة" data-player-game>' +
    '<option value="pubg">PUBG Mobile</option><option value="free_fire">Free Fire</option><option value="efootball">eFootball</option><option value="call_of_duty">Call of Duty</option><option value="other">لعبة أخرى</option>' +
    '</select><input type="text" inputmode="text" placeholder="Player ID" aria-label="معرّف اللاعب" data-player-value><button class="icon-remove" type="button" aria-label="حذف المعرّف"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-trash-2"></use></svg></button>';
  const select = row.querySelector('[data-player-game]');
  const input = row.querySelector('[data-player-value]');
  select.value = [...select.options].some((option) => option.value === game) ? game : 'other';
  input.value = value || '';
  row.querySelector('.icon-remove').addEventListener('click', () => row.remove());
  playerIdList.appendChild(row);
}

function readPlayerIds() {
  const result = {};
  playerIdList.querySelectorAll('.player-id-row').forEach((row) => {
    const game = row.querySelector('[data-player-game]').value;
    const value = row.querySelector('[data-player-value]').value.trim();
    if (value) result[game] = value;
  });
  return result;
}

function renderEmailState() {
  const confirmed = !!(currentUser.email_confirmed_at || currentUser.confirmed_at);
  const pending = sessionStorage.getItem('pending_email_change');
  const isPending = pending && pending.toLowerCase() !== (currentUser.email || '').toLowerCase();
  verifiedBadge.hidden = !confirmed || !!isPending;
  pendingBadge.hidden = !isPending;
  resendConfirmBtn.hidden = confirmed && !isPending;
  if (isPending) {
    emailInput.value = pending;
    pendingBadge.title = 'بانتظار تأكيد: ' + pending;
  }
}

async function loadMfa() {
  const status = document.getElementById('mfaStatus');
  const actions = document.getElementById('mfaActions');
  if (!supabaseClient.auth.mfa) { status.textContent = 'التحقق بخطوتين غير متاح في إصدار المكتبة الحالي.'; return; }
  const { data, error } = await supabaseClient.auth.mfa.listFactors();
  if (error) { status.textContent = 'تعذر قراءة حالة التحقق بخطوتين الآن.'; return; }
  const factor = (data.all || data.totp || []).find((item) => item.factor_type === 'totp' && item.status === 'verified');
  actions.innerHTML = '';
  if (factor) {
    status.innerHTML = '<span style="color: var(--account-ok);font-weight: 800"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-circle-check"></use></svg> التحقق بخطوتين مفعّل عبر Authenticator.</span>';
    const button = document.createElement('button');
    button.className = 'auth-btn danger'; button.type = 'button'; button.innerHTML = '<svg class="mm-i" style="margin-left: 6px" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-shield-half"></use></svg> إيقاف التحقق بخطوتين';
    button.addEventListener('click', () => unenrollMfa(factor.id)); actions.appendChild(button);
  } else {
    status.textContent = 'لم يتم تفعيل التحقق بخطوتين بعد.';
    const button = document.createElement('button');
    button.className = 'auth-btn secondary'; button.type = 'button'; button.innerHTML = '<svg class="mm-i" style="margin-left: 6px" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-smartphone"></use></svg> إعداد Authenticator';
    button.addEventListener('click', enrollMfa); actions.appendChild(button);
  }
}

async function enrollMfa() {
  clearSecurityMessages();
  if (!supabaseClient.auth.mfa) { securityError.textContent = 'التحقق بخطوتين غير متاح الآن.'; return; }
  try {
    const { data, error } = await supabaseClient.auth.mfa.enroll({ factorType: 'totp', friendlyName: 'MEEM STORE Authenticator' });
    if (error) throw error;
    pendingMfaFactor = data;
    document.getElementById('mfaQrCode').src = data.totp.qr_code;
    document.getElementById('mfaSecret').textContent = data.totp.secret;
    document.getElementById('mfaEnrollPanel').hidden = false;
    document.getElementById('mfaCodeInput').focus();
  } catch (_) { securityError.textContent = 'تعذر بدء إعداد Authenticator، حاول مرة أخرى.'; }
}

async function verifyMfa() {
  clearSecurityMessages();
  const code = document.getElementById('mfaCodeInput').value.trim();
  if (!pendingMfaFactor || !/^\d{6}$/.test(code)) { securityError.textContent = 'أدخل رمز Authenticator المكوّن من 6 أرقام.'; return; }
  const button = document.getElementById('mfaVerifyBtn'); UI.setLoading(button, true, 'جارِ التحقق...');
  try {
    const { data: challenge, error: challengeError } = await supabaseClient.auth.mfa.challenge({ factorId: pendingMfaFactor.id });
    if (challengeError) throw challengeError;
    const { error } = await supabaseClient.auth.mfa.verify({ factorId: pendingMfaFactor.id, challengeId: challenge.id, code });
    if (error) throw error;
    document.getElementById('mfaEnrollPanel').hidden = true;
    document.getElementById('mfaCodeInput').value = '';
    pendingMfaFactor = null;
    securitySuccess.textContent = 'تم تفعيل التحقق بخطوتين بنجاح.';
    await loadMfa();
  } catch (_) { securityError.textContent = 'رمز Authenticator غير صحيح أو انتهت صلاحيته.'; }
  finally { UI.setLoading(button, false); }
}

async function unenrollMfa(factorId) {
  clearSecurityMessages();
  const { data: aal, error: aalError } = await supabaseClient.auth.mfa.getAuthenticatorAssuranceLevel();
  if (aalError || aal?.currentLevel !== 'aal2') {
    sessionStorage.setItem('meem_mfa_return', 'account.html');
    window.location.href = 'mfa.html';
    return;
  }
  if (!confirm('هل تريد إيقاف التحقق بخطوتين؟')) return;
  try {
    const { error } = await supabaseClient.auth.mfa.unenroll({ factorId });
    if (error) throw error;
    securitySuccess.textContent = 'تم إيقاف التحقق بخطوتين.';
    await loadMfa();
  } catch (_) { securityError.textContent = 'تعذر إيقاف التحقق بخطوتين.'; }
}

function renderAvatar(url) {
  const summaryImg = document.getElementById('summaryAvatarImg');
  const profileImg = document.getElementById('profileAvatarImg');
  [summaryImg, profileImg].forEach((img) => {
    if (!img) return;
    if (url) { img.src = url; img.hidden = false; } else { img.removeAttribute('src'); img.hidden = true; }
  });
  document.querySelectorAll('#summaryAvatar > svg, #profilePhotoPreview > svg').forEach((icon) => {
    // عناصر SVG لا تدعم خاصية hidden كخاصية DOM — نستخدم السمة مباشرة
    if (url) icon.setAttribute('hidden', ''); else icon.removeAttribute('hidden');
  });
}

async function init() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return; }
  const { data: { user } } = await supabaseClient.auth.getUser();
  currentUser = user || session.user;
  document.getElementById('summaryName').textContent = currentUser.user_metadata?.full_name || 'حساب MEEM STORE';
  document.getElementById('summaryEmail').textContent = currentUser.email || '—';
  emailInput.value = currentUser.email || '';
  renderEmailState();
  await loadMfa();
  let { data: profile, error: profileError } = await supabaseClient.from('profiles').select('full_name,whatsapp_number,referral_code,player_ids,avatar_url').eq('id', currentUser.id).single();
  if (profileError && /avatar_url|player_ids|column/i.test(profileError.message || '')) {
    const fallback = await supabaseClient.from('profiles').select('full_name,whatsapp_number,referral_code').eq('id', currentUser.id).single();
    profile = fallback.data || {};
  }
  currentProfile = profile || {};
  document.getElementById('fullNameInput').value = currentProfile.full_name || currentUser.user_metadata?.full_name || '';
  document.getElementById('whatsappInput').value = currentProfile.whatsapp_number || '';
  renderPlayerIds(currentProfile.player_ids || {});
  renderAvatar(currentProfile.avatar_url || '');
  currencySelect.value = localStorage.getItem('meem_preferred_currency') || 'SDG';
  openFromHash();
}

async function saveProfile() {
  clearMessages();
  const fullName = document.getElementById('fullNameInput').value.trim();
  const whatsapp = document.getElementById('whatsappInput').value.trim();
  const newEmail = emailInput.value.trim();
  const oldEmail = (currentUser.email || '').trim();
  if (!fullName) { formError.textContent = 'أدخل اسمك الكامل.'; return; }
  if (!UI.isValidEmail(newEmail)) { formError.textContent = 'أدخل بريدًا إلكترونيًا صالحًا.'; return; }
  const emailChanged = newEmail.toLowerCase() !== oldEmail.toLowerCase();
  const pendingEmail = sessionStorage.getItem('pending_email_change');
  const alreadyPending = pendingEmail && pendingEmail.toLowerCase() === newEmail.toLowerCase();
  UI.setLoading(saveBtn, true, 'جارِ الحفظ...');
  try {
    if (emailChanged && !alreadyPending) { const verified = await requestReauthentication('تغيير البريد الإلكتروني', 'session'); if (!verified) return; }
    const { error: profileError } = await supabaseClient.from('profiles').update({ full_name: fullName, whatsapp_number: whatsapp, player_ids: readPlayerIds() }).eq('id', currentUser.id);
    if (profileError) throw profileError;
    if (emailChanged && !alreadyPending) {
      const { error: emailError } = await supabaseClient.auth.updateUser({ email: newEmail });
      if (emailError) throw emailError;
      sessionStorage.setItem('pending_email_change', newEmail); pendingBadge.hidden = false; verifiedBadge.hidden = true;
      formSuccess.textContent = 'تم الحفظ. تحقق من بريدك الجديد (والقديم) لتأكيد التغيير.';
    } else if (alreadyPending) {
      formSuccess.textContent = 'ما زال تغيير البريد بانتظار التأكيد من بريدك الجديد والقديم.';
    } else { formSuccess.textContent = 'تم حفظ البيانات الشخصية بنجاح.'; }
    document.getElementById('summaryName').textContent = fullName;
    setTimeout(() => { formSuccess.textContent = ''; }, 4500);
  } catch (_) { formError.textContent = 'حصل خطأ أثناء الحفظ، حاول مرة أخرى.'; }
  finally { UI.setLoading(saveBtn, false); }
}

async function resendConfirmation() {
  clearMessages();
  try {
    const pendingEmail = sessionStorage.getItem('pending_email_change');
    const { error } = await supabaseClient.auth.resend({
      type: pendingEmail ? 'email_change' : 'signup',
      email: pendingEmail || currentUser.email
    });
    if (error) throw error;
    formSuccess.textContent = pendingEmail
      ? 'تمت إعادة إرسال رسالة تأكيد تغيير البريد.'
      : 'تم إرسال رسالة تأكيد جديدة إلى بريدك.';
  } catch (_) { formError.textContent = 'تعذر إرسال رسالة التأكيد الآن.'; }
}

async function startPasswordChange() {
  clearSecurityMessages();
  const button = document.getElementById('startPasswordChangeBtn');
  UI.setLoading(button, true, 'جارِ إرسال الكود...');
  try {
    const verified = await requestReauthentication('تغيير كلمة المرور', 'password');
    if (!verified) return;
    pendingPasswordNonce = verified.nonce;
    document.getElementById('passwordIntro').hidden = true;
    document.getElementById('passwordFormStage').hidden = false;
    document.getElementById('newPasswordInput').focus();
    securitySuccess.textContent = 'تم تأكيد بريدك بالكود. أدخل كلمة المرور الجديدة ثم احفظها.';
  } finally { UI.setLoading(button, false); }
}

async function changePassword() {
  clearSecurityMessages();
  if (!pendingPasswordNonce) { securityError.textContent = 'ابدأ بتأكيد بريدك أولاً.'; return; }
  const newPassword = document.getElementById('newPasswordInput').value;
  const confirmPassword = document.getElementById('confirmPasswordInput').value;
  if (newPassword.length < 8 || !/[A-Za-z]/.test(newPassword) || !/[0-9]/.test(newPassword)) { securityError.textContent = 'كلمة السر يجب أن تحتوي على 8 أحرف ورقم واحد على الأقل.'; return; }
  if (newPassword !== confirmPassword) { securityError.textContent = 'كلمتا السر غير متطابقتين.'; return; }
  const button = document.getElementById('changePasswordBtn'); UI.setLoading(button, true, 'جارِ التحقق...');
  try {
    const { error } = await supabaseClient.auth.updateUser({ password: newPassword, nonce: pendingPasswordNonce });
    if (error) throw error;
    document.getElementById('newPasswordInput').value = ''; document.getElementById('confirmPasswordInput').value = '';
    pendingPasswordNonce = '';
    document.getElementById('passwordFormStage').hidden = true;
    document.getElementById('passwordIntro').hidden = false;
    securitySuccess.textContent = 'تم تغيير كلمة السر بنجاح.';
  } catch (error) {
    pendingPasswordNonce = '';
    document.getElementById('passwordFormStage').hidden = true;
    document.getElementById('passwordIntro').hidden = false;
    securityError.textContent = error?.message?.toLowerCase().includes('nonce') ? 'انتهت صلاحية كود التأكيد. أعد طلب كود جديد.' : 'تعذر تغيير كلمة السر، حاول مرة أخرى.';
  }
  finally { UI.setLoading(button, false); }
}

async function uploadAvatar(file) {
  if (!file) return;
  clearMessages();
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) { avatarStatus.textContent = 'اختر صورة JPG أو PNG أو WEBP فقط.'; return; }
  if (file.size > 5 * 1024 * 1024) { avatarStatus.textContent = 'حجم الصورة أكبر من 5MB.'; return; }
  avatarStatus.textContent = 'جارِ رفع الصورة...';
  try {
    const extension = file.type.split('/')[1].replace('jpeg', 'jpg');
    const path = currentUser.id + '/' + crypto.randomUUID() + '.' + extension;
    const { error: uploadError } = await supabaseClient.storage.from('avatars').upload(path, file, { upsert: false, contentType: file.type, cacheControl: '3600' });
    if (uploadError) throw uploadError;
    const { data: urlData } = supabaseClient.storage.from('avatars').getPublicUrl(path);
    const { error: profileError } = await supabaseClient.from('profiles').update({ avatar_url: urlData.publicUrl }).eq('id', currentUser.id);
    if (profileError) throw profileError;
    avatarPath = path;
    renderAvatar(urlData.publicUrl);
    avatarStatus.textContent = 'تم حفظ الصورة الشخصية.';
  } catch (error) {
    avatarStatus.textContent = error?.message?.toLowerCase().includes('bucket') ? 'لم يتم إعداد مساحة الصور بعد. طبّق migration الخاصة بالصور.' : 'تعذر رفع الصورة، حاول مرة أخرى.';
  } finally { avatarInput.value = ''; }
}

async function globalSignOut() {
  clearSecurityMessages();
  const verified = await requestReauthentication('تسجيل الخروج من كل الأجهزة', 'session');
  if (!verified) return;
  const { error } = await supabaseClient.auth.signOut({ scope: 'global' });
  if (error) { securityError.textContent = 'تعذر تسجيل الخروج من كل الأجهزة.'; return; }
  window.location.href = 'login.html';
}

async function logout() { await supabaseClient.auth.signOut({ scope: 'local' }); window.location.href = 'index.html'; }

document.getElementById('addPlayerIdBtn').addEventListener('click', () => addPlayerIdRow('other', ''));
document.getElementById('mfaVerifyBtn').addEventListener('click', verifyMfa);
document.getElementById('resendConfirmBtn').addEventListener('click', resendConfirmation);
document.getElementById('saveBtn').addEventListener('click', saveProfile);
document.getElementById('startPasswordChangeBtn').addEventListener('click', startPasswordChange);
document.getElementById('changePasswordBtn').addEventListener('click', changePassword);
avatarInput.addEventListener('change', () => uploadAvatar(avatarInput.files[0]));
document.getElementById('globalSignOutBtn').addEventListener('click', globalSignOut);
document.getElementById('logoutBtn').addEventListener('click', logout);
currencySelect.addEventListener('change', () => localStorage.setItem('meem_preferred_currency', currencySelect.value));

document.getElementById('reauthForm').addEventListener('submit', async (event) => {
  event.preventDefault(); reauthError.textContent = '';
  const code = reauthOtp.value();
  if (code.length !== 6) { reauthError.textContent = 'أدخل الكود كاملاً (6 أرقام).'; return; }
  UI.setLoading(reauthVerifyBtn, true, 'جارِ التحقق...');
  try {
    if (reauthMode === 'password') { closeReauth({ nonce: code }); return; }
    const { data, error } = await supabaseClient.auth.verifyOtp({ email: reauthEmail, token: code, type: 'email' });
    if (error) { reauthError.textContent = error.status === 429 ? 'محاولات كثيرة، حاول مرة أخرى بعد قليل.' : 'الكود غير صحيح أو منتهي الصلاحية.'; reauthOtp.clear(); return; }
    closeReauth({ sessionVerified: true, session: data.session || null });
  } catch (_) { reauthError.textContent = 'تعذر التحقق الآن، حاول مرة أخرى.'; }
  finally { UI.setLoading(reauthVerifyBtn, false); }
});
document.getElementById('reauthResendBtn').addEventListener('click', () => sendReauthCode().catch(() => { reauthError.textContent = 'تعذرت إعادة إرسال الكود.'; }));
document.getElementById('reauthCancelBtn').addEventListener('click', () => closeReauth(false));
reauthModal.addEventListener('click', (event) => { if (event.target === reauthModal) closeReauth(false); });
document.addEventListener('keydown', (event) => { if (event.key === 'Escape' && !reauthModal.hidden) closeReauth(false); });

init();
