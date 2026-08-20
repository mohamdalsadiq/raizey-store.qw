(() => {
  'use strict';
  if (window.__RAIZEY_ASSISTANT_LOADED__) return;
  window.__RAIZEY_ASSISTANT_LOADED__ = true;

  const style = document.createElement('style');
  style.textContent = `
    #raizeyAssistantRoot{position:fixed;inset:auto 20px 20px auto;z-index:9998;font-family:inherit;direction:rtl}
    #raizeyAssistantToggle{width:58px;height:58px;border:0;border-radius:50%;background:linear-gradient(135deg,#ff7a2f,#e5482e);color:#fff;box-shadow:0 12px 30px rgba(229,72,46,.32);cursor:pointer;font-size:24px;display:grid;place-items:center;transition:transform .2s,box-shadow .2s}
    #raizeyAssistantToggle:hover{transform:translateY(-2px);box-shadow:0 16px 36px rgba(229,72,46,.4)}
    #raizeyAssistantPanel{position:absolute;right:0;bottom:72px;width:min(390px,calc(100vw - 32px));height:min(590px,calc(100vh - 112px));background:#fff;border:1px solid rgba(20,31,48,.11);border-radius:22px;box-shadow:0 24px 70px rgba(20,31,48,.2);display:none;overflow:hidden}
    #raizeyAssistantPanel.is-open{display:flex;flex-direction:column;animation:raizeyAssistantIn .18s ease-out}
    @keyframes raizeyAssistantIn{from{opacity:0;transform:translateY(10px) scale(.98)}to{opacity:1;transform:none}}
    .raizey-assistant-head{display:flex;align-items:center;gap:11px;padding:16px 17px;background:linear-gradient(135deg,#fff7f1,#fff);border-bottom:1px solid #f1e6df}
    .raizey-assistant-avatar{width:40px;height:40px;border-radius:13px;display:grid;place-items:center;background:#ffeadc;color:#e45125;font-size:19px}
    .raizey-assistant-title{flex:1;color:#172033;font-size:15px;font-weight:900;line-height:1.35}
    .raizey-assistant-title small{display:block;color:#708096;font-size:11px;font-weight:600;margin-top:2px}
    .raizey-assistant-close{border:0;background:transparent;color:#8090a4;cursor:pointer;font-size:18px;padding:5px}
    .raizey-assistant-messages{flex:1;overflow:auto;padding:16px 14px;background:#fbfcfe;scroll-behavior:smooth}
    .raizey-assistant-msg{max-width:88%;padding:10px 12px;border-radius:15px;margin:0 0 10px;font-size:13px;line-height:1.7;white-space:pre-wrap;word-break:break-word}
    .raizey-assistant-msg.assistant{margin-left:auto;background:#fff;border:1px solid #edf0f4;color:#263348;border-top-right-radius:5px}
    .raizey-assistant-msg.user{margin-right:auto;background:#e9512a;color:#fff;border-top-left-radius:5px}
    .raizey-assistant-msg a{color:#e45125;font-weight:800}
    .raizey-assistant-quick{display:flex;gap:7px;overflow:auto;padding:0 14px 11px;background:#fbfcfe}
    .raizey-assistant-quick button{flex:0 0 auto;border:1px solid #f0d3c3;background:#fff7f1;color:#b74728;border-radius:999px;padding:7px 10px;font:inherit;font-size:11px;cursor:pointer}
    .raizey-assistant-form{display:flex;align-items:flex-end;gap:8px;padding:11px;border-top:1px solid #edf0f4;background:#fff}
    .raizey-assistant-input{min-width:0;flex:1;resize:none;max-height:100px;border:1px solid #dce3eb;border-radius:13px;padding:10px 11px;color:#172033;background:#fff;font:inherit;font-size:13px;outline:0;line-height:1.5}
    .raizey-assistant-input:focus{border-color:#ed754b;box-shadow:0 0 0 3px rgba(237,117,75,.12)}
    .raizey-assistant-send{width:40px;height:40px;border:0;border-radius:12px;background:#e9512a;color:#fff;cursor:pointer;font-size:15px;display:grid;place-items:center}
    .raizey-assistant-send:disabled{opacity:.55;cursor:wait}
    .raizey-assistant-typing{color:#7d8ca0;font-size:12px;padding:0 3px 9px}
    @media(max-width:520px){#raizeyAssistantRoot{right:16px;bottom:16px}#raizeyAssistantPanel{right:-2px;bottom:70px;height:min(580px,calc(100vh - 100px))}}
  `;
  document.head.appendChild(style);

  const root = document.createElement('div');
  root.id = 'raizeyAssistantRoot';
  root.innerHTML = `
    <section id="raizeyAssistantPanel" aria-label="مساعد Raizey" aria-hidden="true">
      <header class="raizey-assistant-head">
        <div class="raizey-assistant-avatar"><i class="fas fa-sparkles" aria-hidden="true"></i></div>
        <div class="raizey-assistant-title">مساعد Raizey<small>المنتجات والطلبات في مكان واحد</small></div>
        <button class="raizey-assistant-close" type="button" aria-label="إغلاق المساعد"><i class="fas fa-xmark"></i></button>
      </header>
      <div class="raizey-assistant-messages" id="raizeyAssistantMessages"></div>
      <div class="raizey-assistant-quick">
        <button type="button" data-assistant-message="ما هي حالة طلباتي؟">حالة طلباتي</button>
        <button type="button" data-assistant-message="أريد البحث عن منتج">البحث عن منتج</button>
      </div>
      <div class="raizey-assistant-typing" id="raizeyAssistantTyping" hidden>المساعد يكتب الآن...</div>
      <form class="raizey-assistant-form" id="raizeyAssistantForm">
        <textarea class="raizey-assistant-input" id="raizeyAssistantInput" rows="1" maxlength="1200" placeholder="اكتب سؤالك هنا..." aria-label="رسالتك"></textarea>
        <button class="raizey-assistant-send" id="raizeyAssistantSend" type="submit" aria-label="إرسال"><i class="fas fa-paper-plane"></i></button>
      </form>
    </section>
    <button id="raizeyAssistantToggle" type="button" aria-label="فتح مساعد Raizey" aria-expanded="false"><i class="fas fa-sparkles"></i></button>
  `;
  document.body.appendChild(root);

  const panel = root.querySelector('#raizeyAssistantPanel');
  const toggle = root.querySelector('#raizeyAssistantToggle');
  const close = root.querySelector('.raizey-assistant-close');
  const messages = root.querySelector('#raizeyAssistantMessages');
  const form = root.querySelector('#raizeyAssistantForm');
  const input = root.querySelector('#raizeyAssistantInput');
  const send = root.querySelector('#raizeyAssistantSend');
  const typing = root.querySelector('#raizeyAssistantTyping');
  const history = [];

  function addMessage(role, text) {
    const element = document.createElement('div');
    element.className = `raizey-assistant-msg ${role}`;
    element.textContent = text;
    messages.appendChild(element);
    messages.scrollTop = messages.scrollHeight;
    history.push({ role, content: text });
  }

  function openPanel() {
    panel.classList.add('is-open');
    panel.setAttribute('aria-hidden', 'false');
    toggle.setAttribute('aria-expanded', 'true');
    if (!messages.children.length) addMessage('assistant', 'مرحباً بك. أستطيع مساعدتك في البحث عن المنتجات ومعرفة حالة طلباتك. كيف يمكنني خدمتك؟');
    setTimeout(() => input.focus(), 50);
  }
  function closePanel() {
    panel.classList.remove('is-open');
    panel.setAttribute('aria-hidden', 'true');
    toggle.setAttribute('aria-expanded', 'false');
  }

  async function sendMessage(text) {
    const message = String(text || '').trim();
    if (!message || send.disabled) return;
    addMessage('user', message);
    input.value = '';
    input.style.height = 'auto';
    send.disabled = true;
    typing.hidden = false;
    try {
      if (!window.supabaseClient || typeof window.supabaseClient.functions?.invoke !== 'function') {
        throw new Error('client_not_ready');
      }
      const recentHistory = history.slice(-9, -1);
      const { data, error } = await window.supabaseClient.functions.invoke('chat-assistant', {
        body: { message, history: recentHistory },
      });
      if (error || !data?.answer) throw error || new Error('empty_answer');
      addMessage('assistant', data.answer);
    } catch (error) {
      const status = error?.context?.status || error?.status;
      addMessage('assistant', status === 401
        ? 'يرجى تسجيل الدخول أولاً حتى أتمكن من الوصول إلى بيانات طلباتك.'
        : 'تعذر الاتصال بالمساعد حالياً. حاول مرة أخرى بعد قليل أو تواصل مع الدعم.');
    } finally {
      send.disabled = false;
      typing.hidden = true;
      input.focus();
    }
  }

  toggle.addEventListener('click', () => panel.classList.contains('is-open') ? closePanel() : openPanel());
  close.addEventListener('click', closePanel);
  root.querySelectorAll('[data-assistant-message]').forEach((button) => {
    button.addEventListener('click', () => sendMessage(button.getAttribute('data-assistant-message')));
  });
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    sendMessage(input.value);
  });
  input.addEventListener('input', () => {
    input.style.height = 'auto';
    input.style.height = `${Math.min(input.scrollHeight, 100)}px`;
  });
  input.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      form.requestSubmit();
    }
  });
})();
