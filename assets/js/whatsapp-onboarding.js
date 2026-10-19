/* Contact completion is server-checked; no user metadata or cached flag is trusted. */
(function () {
  'use strict';
  const client = window.supabaseClient;
  if (!client || window.MeemAuthFlow?.isAuthPage()) return;
  let dialog, input, errorBox, save, retry, form, countryBox, picker, pickerLoading, busy = false, generation = 0;
  function node(tag, cls, text) {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text) n.textContent = text;
    return n;
  }
  function build() {
    if (dialog) return;
    dialog = node('dialog', 'wa-onboarding');
    dialog.id = 'whatsappOnboarding';
    dialog.dir = 'rtl';
    dialog.setAttribute('aria-labelledby', 'waHeading');
    dialog.setAttribute('aria-describedby', 'waDescription');
    const mark = node('img', 'wa-mark');
    mark.src = 'assets/img/meem-mark-192.png'; mark.alt = 'MEEM STORE'; mark.width = 56; mark.height = 56;
    const title = node('h2', '', 'خلّينا نتابع طلباتك معاك'); title.id = 'waHeading';
    const description = node('p', 'wa-description', 'يجب إضافة رقم الواتساب الخاص بك لمتابعة طلباتك والتواصل معك عند الحاجة.');
    description.id = 'waDescription';
    form = node('form'); form.noValidate = true;
    const label = node('label', '', 'رقم واتساب'); label.htmlFor = 'waPhone';
    input = node('input'); input.id = 'waPhone'; input.type = 'tel'; input.dir = 'ltr';
    input.autocomplete = 'tel'; input.inputMode = 'tel'; input.maxLength = 32; input.required = true;
    input.placeholder = '912 345 678';
    input.setAttribute('aria-describedby', 'waHint waError');
    const hint = node('p', 'wa-hint', 'اختر الدولة ثم أدخل رقمك المحلي كاملًا. سنضيف رمز الدولة تلقائيًا.'); hint.id = 'waHint';
    errorBox = node('p', 'wa-error'); errorBox.id = 'waError'; errorBox.setAttribute('role', 'alert');
    input.addEventListener('input', () => { errorBox.textContent = ''; input.removeAttribute('aria-invalid'); });
    save = node('button', 'wa-save', 'حفظ الرقم ومتابعة التسوق'); save.type = 'submit';
    retry = node('button', 'wa-retry', 'إعادة المحاولة'); retry.type = 'button'; retry.hidden = true;
    retry.addEventListener('click', () => check(++generation));
    countryBox = node('div');
    form.append(countryBox, label, input, hint, errorBox, save, retry);
    const privacy = node('p', 'wa-privacy', 'يمكنك تعديل الرقم لاحقًا من حسابك. لا نعرضه لزوار المتجر.');
    const logout = node('button', 'wa-logout', 'تسجيل الخروج'); logout.type = 'button';
    logout.addEventListener('click', async () => {
      logout.disabled = true;
      try {
        const { error } = await client.auth.signOut({ scope: 'local' });
        if (error) throw error;
        location.replace('login.html');
      } catch (_) { errorBox.textContent = 'تعذر تسجيل الخروج. أعد المحاولة.'; logout.disabled = false; }
    });
    dialog.append(mark, title, description, form, privacy, logout);
    dialog.addEventListener('cancel', event => event.preventDefault());
    form.addEventListener('submit', async event => {
      event.preventDefault();
      if (busy || save.disabled) return;
      errorBox.textContent = ''; input.removeAttribute('aria-invalid');
      const number = picker?.number();
      if (!number) {
        errorBox.textContent = 'أدخل رقمًا صحيحًا ومكتملًا في ' + (picker?.name || 'الدولة المختارة') + '. تأكد من الدولة ومقدمة الرقم.'; input.setAttribute('aria-invalid', 'true'); input.focus(); return;
      }
      busy = true; save.disabled = true; save.textContent = 'جارِ حفظ الرقم…';
      try {
        const { data, error } = await client.rpc('complete_whatsapp_onboarding', { p_phone: number, p_country: picker.country });
        if (error || data?.completed !== true) throw error || new Error('save_failed');
        dialog.close();
        window.dispatchEvent(new CustomEvent('meem:profile-completed'));
      } catch (err) {
        input.setAttribute('aria-invalid', 'true');
        errorBox.textContent = String(err?.message).includes('invalid_whatsapp')
          ? 'الرقم غير صحيح أو لا يتبع الدولة المختارة. تحقق من الدولة والرقم كاملًا.'
          : 'تعذر حفظ الرقم. تحقق من الاتصال وحاول مرة أخرى.';
        input.focus();
      } finally { busy = false; save.disabled = false; save.textContent = 'حفظ الرقم ومتابعة التسوق'; }
    });
    document.body.appendChild(dialog);
  }
  async function show(failed) {
    build();
    if (!picker) {
      try {
        if (!pickerLoading) pickerLoading = window.MeemPhonePicker.create(countryBox, input);
        picker = await pickerLoading;
      } catch (_) { pickerLoading = null; failed = true; }
    }
    save.disabled = !!failed; input.disabled = !!failed; retry.hidden = !failed;
    errorBox.textContent = failed ? 'تعذر التأكد من بيانات حسابك. أعد المحاولة للمتابعة.' : '';
    if (!dialog.open) dialog.showModal();
    (failed ? retry : input).focus();
  }
  async function check(version) {
    try {
      const { data, error } = await client.auth.getSession();
      if (version !== generation) return;
      if (error) throw error;
      if (!data?.session) { if (dialog?.open) dialog.close(); return; }
      if (!(await window.MeemAuthFlow.ensureMfa(location.pathname + location.search + location.hash))) return;
      const result = await client.rpc('get_own_onboarding_status');
      if (version !== generation) return;
      if (result.error) throw result.error;
      if (result.data?.has_whatsapp === true) { if (dialog?.open) dialog.close(); }
      else await show(false);
    } catch (_) { if (version === generation) await show(true); }
  }
  // Never await Supabase from inside its auth callback (the SDK holds a lock).
  client.auth.onAuthStateChange(() => { const version = ++generation; setTimeout(() => check(version), 0); });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => check(++generation));
  else check(++generation);
})();
