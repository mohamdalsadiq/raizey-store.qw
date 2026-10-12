(() => {
  'use strict';
  if (window.__MEEM_ASSISTANT_LOADED__) return;
  window.__MEEM_ASSISTANT_LOADED__ = true;

  // ── Draggable floating assistant ───────────────────────────────────────────
  // The toggle can be dragged anywhere on screen and its position is remembered
  // in localStorage. A comfort zone (EDGE) plus the bottom-nav height guarantee
  // it never covers the bottom navigation or important content at rest.
  const POS_KEY = 'raizey-assistant-pos';
  const FAB = 54;
  const EDGE = 12;
  const BOTTOM_NAV = 76;
  const GAP = 12;

  const style = document.createElement('style');
  style.textContent = `
    #meemAssistantRoot{position: fixed;right: 18px;bottom: 18px;z-index: 9998;font-family: inherit;direction: rtl}
    body.mm-has-bottom-nav #meemAssistantRoot{bottom:calc(${BOTTOM_NAV}px + env(safe-area-inset-bottom))}
    #meemAssistantToggle{width:${FAB}px;height:${FAB}px;border: 0;border-radius: 50%;background: linear-gradient(135deg,var(--mm-gold-400),var(--mm-gold-600));color: var(--mm-royal-950);box-shadow: 0 10px 26px rgba(255, 212, 0,.34);cursor: grab;font-size: 26px;display: grid;place-items: center;transition: transform .2s,box-shadow .2s;touch-action: none;-webkit-user-select: none;user-select: none;-webkit-tap-highlight-color: transparent}
    #meemAssistantToggle:hover{transform: translateY(-2px);box-shadow: 0 14px 32px rgba(8, 123, 255,.45)}
    #meemAssistantToggle.mm-dragging{cursor: grabbing;transition: none;transform: scale(1.06)}
    #meemAssistantToggle svg{pointer-events: none;width: 28px;height: 28px;display: block}
    .meem-assistant-avatar svg{width: 24px;height: 24px;display: block}
    #meemAssistantPanel{position: fixed;left: auto;right: auto;top: auto;bottom: auto;width: min(390px,calc(100vw - 24px));height: min(560px,calc(100vh - 24px));background: var(--mm-surface);border: 1px solid var(--mm-border);border-radius: 22px;box-shadow: var(--mm-shadow-lg);display: none;overflow: hidden;z-index: 9999}
    #meemAssistantPanel.is-open{display: flex;flex-direction: column;animation: meemAssistantIn .18s ease-out}
    @keyframes meemAssistantIn{from{opacity: 0;transform: translateY(10px) scale(.98)}to{opacity: 1;transform: none}}
    .meem-assistant-head{display: flex;align-items: center;gap: 11px;padding: 16px 17px;background: linear-gradient(135deg,var(--mm-royal),var(--mm-royal-700));border-bottom: 1px solid var(--mm-border);color: var(--mm-silver)}
    .meem-assistant-avatar{width: 40px;height: 40px;border-radius: 13px;display: grid;place-items: center;background: var(--mm-gold-tint-2);color: var(--mm-gold);font-size: 19px}
    .meem-assistant-title{flex: 1;color: var(--mm-silver);font-size: 15px;font-weight: 900;line-height: 1.35}
    .meem-assistant-title small{display: block;color: var(--mm-ice-soft);font-size: 11px;font-weight: 600;margin-top: 2px}
    .meem-assistant-close{border: 0;background: transparent;color: var(--mm-ice-soft);cursor: pointer;font-size: 18px;padding: 5px}
    .meem-assistant-messages{flex: 1;overflow: auto;padding: 16px 14px;background: var(--mm-bg);scroll-behavior: smooth}
    .meem-assistant-msg{max-width: 88%;padding: 10px 12px;border-radius: 15px;margin: 0 0 10px;font-size: 13px;line-height: 1.7;white-space: pre-wrap;word-break: break-word}
    .meem-assistant-msg.assistant{margin-left: auto;background: var(--mm-surface-2);border: 1px solid var(--mm-border);color: var(--mm-text);border-top-right-radius: 5px}
    .meem-assistant-msg.user{margin-right: auto;background: var(--mm-royal-500);color: var(--mm-silver);border-top-left-radius: 5px}
    .meem-assistant-msg a{color: var(--mm-gold);font-weight: 800}
    .meem-assistant-quick{display: flex;gap: 7px;overflow: auto;padding: 0 14px 11px;background: var(--mm-surface)}
    .meem-assistant-quick button{flex: 0 0 auto;border: 1px solid var(--mm-border);background: var(--mm-surface-2);color: var(--mm-gold);border-radius: 999px;padding: 7px 10px;font: inherit;font-size: 11px;cursor: pointer}
    .meem-assistant-form{display: flex;align-items: flex-end;gap: 8px;padding: 11px;border-top: 1px solid var(--mm-border);background: var(--mm-surface)}
    .meem-assistant-input{min-width: 0;flex: 1;resize: none;max-height: 100px;border: 1px solid var(--mm-border);border-radius: 13px;padding: 10px 11px;color: var(--mm-text);background: var(--mm-surface-2);font: inherit;font-size: 13px;outline: 0;line-height: 1.5}
    .meem-assistant-input:focus{border-color: var(--mm-electric);box-shadow: 0 0 0 3px var(--mm-electric-tint)}
    .meem-assistant-send{width: 40px;height: 40px;border: 0;border-radius: 12px;background: var(--mm-gold);color: var(--mm-royal-950);cursor: pointer;font-size: 15px;display: grid;place-items: center}
    .meem-assistant-send:disabled{opacity: .55;cursor: wait}
    .meem-assistant-typing{color: var(--mm-text-muted);font-size: 12px;padding: 0 3px 9px}
  `;
  document.head.appendChild(style);

  const root = document.createElement('div');
  root.id = 'meemAssistantRoot';
  root.innerHTML = `
    <section id="meemAssistantPanel" aria-label="مساعد MEEM الذكي" aria-hidden="true">
      <header class="meem-assistant-head">
        <div class="meem-assistant-avatar"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-bot"></use></svg></div>
        <div class="meem-assistant-title">مساعد MEEM الذكي<small>المنتجات والطلبات في مكان واحد</small></div>
        <button class="meem-assistant-close" type="button" aria-label="إغلاق المساعد"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-x"></use></svg></button>
      </header>
      <div class="meem-assistant-messages" id="meemAssistantMessages"></div>
      <div class="meem-assistant-quick">
        <button type="button" data-assistant-message="ما هي حالة طلباتي؟">حالة طلباتي</button>
        <button type="button" data-assistant-message="أريد البحث عن منتج">البحث عن منتج</button>
      </div>
      <div class="meem-assistant-typing" id="meemAssistantTyping" hidden>المساعد يكتب الآن...</div>
      <form class="meem-assistant-form" id="meemAssistantForm">
        <textarea class="meem-assistant-input" id="meemAssistantInput" rows="1" maxlength="1200" placeholder="اكتب سؤالك هنا..." aria-label="رسالتك"></textarea>
        <button class="meem-assistant-send" id="meemAssistantSend" type="submit" aria-label="إرسال"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-send"></use></svg></button>
      </form>
    </section>
    <button id="meemAssistantToggle" type="button" aria-label="مساعد الذكاء الاصطناعي — اسحب لتحريكه" aria-expanded="false" title="اسحب الزر لتحريكه في أي مكان"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-bot"></use></svg></button>
  `;
  document.body.appendChild(root);

  const panel = root.querySelector('#meemAssistantPanel');
  const toggle = root.querySelector('#meemAssistantToggle');
  const close = root.querySelector('.meem-assistant-close');
  const messages = root.querySelector('#meemAssistantMessages');
  const form = root.querySelector('#meemAssistantForm');
  const input = root.querySelector('#meemAssistantInput');
  const send = root.querySelector('#meemAssistantSend');
  const typing = root.querySelector('#meemAssistantTyping');
  const history = [];

  /* ── Floating position (drag + persistence) ───────────────────────────── */
  function navReserve() {
    return document.body && document.body.classList.contains('mm-has-bottom-nav') ? BOTTOM_NAV:  0;
  }
  function clampPosition(x, y) {
    const w = toggle.offsetWidth || FAB;
    const h = toggle.offsetHeight || FAB;
    const maxX = Math.max(EDGE, window.innerWidth - w - EDGE);
    const maxY = Math.max(EDGE, window.innerHeight - h - EDGE - navReserve());
    return { x: Math.min(Math.max(EDGE, x), maxX), y: Math.min(Math.max(EDGE, y), maxY) };
  }
  function place(x, y) {
    const p = clampPosition(x, y);
    root.style.left = p.x + 'px';
    root.style.top = p.y + 'px';
    root.style.right = 'auto';
    root.style.bottom = 'auto';
    return p;
  }
  function isFloating() { return root.style.left !== ''; }
  function savePosition(p) { try { localStorage.setItem(POS_KEY, JSON.stringify(p)); } catch (e) {} }
  function loadPosition() {
    try {
      const raw = localStorage.getItem(POS_KEY);
      if (!raw) return null;
      const p = JSON.parse(raw);
      if (p && typeof p.x === 'number' && typeof p.y === 'number') return p;
    } catch (e) {}
    return null;
  }
  function restorePosition() {
    const p = loadPosition();
    if (p) place(p.x, p.y);
  }
  function reflowPosition() {
    if (isFloating()) savePosition(place(root.offsetLeft, root.offsetTop));
  }
  window.addEventListener('resize', reflowPosition);
  window.addEventListener('orientationchange', reflowPosition);

  let dragging = null;
  let suppressToggle = false;

  // Listeners live on window (not the toggle) so the drag keeps working even
  // when the button slides out from under the pointer — pointer capture is not
  // reliable in every engine, so this is the robust path.
  function onPointerMove(event) {
    if (!dragging || event.pointerId !== dragging.id) return;
    if (!dragging.moved &&
        Math.abs(event.clientX - dragging.startX) < 5 &&
        Math.abs(event.clientY - dragging.startY) < 5) return;
    dragging.moved = true;
    place(event.clientX - dragging.offX, event.clientY - dragging.offY);
  }
  function onPointerUp(event) {
    if (!dragging || event.pointerId !== dragging.id) return;
    window.removeEventListener('pointermove', onPointerMove);
    window.removeEventListener('pointerup', onPointerUp);
    window.removeEventListener('pointercancel', onPointerUp);
    toggle.classList.remove('mm-dragging');
    if (dragging.moved) {
      savePosition(place(root.offsetLeft, root.offsetTop));
      suppressToggle = true;
      setTimeout(() => { suppressToggle = false; }, 350);
    }
    dragging = null;
  }
  toggle.addEventListener('pointerdown', (event) => {
    if (event.button && event.button !== 0) return;
    const rect = root.getBoundingClientRect();
    dragging = {
      id: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      offX: event.clientX - rect.left,
      offY: event.clientY - rect.top,
      moved: false
    };
    if (event.cancelable) event.preventDefault();
    toggle.classList.add('mm-dragging');
    window.addEventListener('pointermove', onPointerMove);
    window.addEventListener('pointerup', onPointerUp);
    window.addEventListener('pointercancel', onPointerUp);
  });

  /* ── Panel placement: keep it fully inside the viewport ───────────────── */
  function positionPanel() {
    const rect = toggle.getBoundingClientRect();
    const gap = GAP;
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const pw = Math.min(panel.offsetWidth || 360, vw - 2 * EDGE);
    const ph = Math.min(panel.offsetHeight || 520, vh - 2 * EDGE);

    let left = (rect.left + rect.width / 2 < vw / 2) ? rect.left:  rect.right - pw;
    left = Math.min(Math.max(EDGE, left), Math.max(EDGE, vw - pw - EDGE));

    const spaceAbove = rect.top;
    const spaceBelow = vh - rect.bottom;
    let top = (spaceAbove >= ph + gap || spaceAbove >= spaceBelow) ? rect.top - ph - gap:  rect.bottom + gap;
    top = Math.min(Math.max(EDGE, top), Math.max(EDGE, vh - ph - EDGE));

    panel.style.left = left + 'px';
    panel.style.top = top + 'px';
    panel.style.right = 'auto';
    panel.style.bottom = 'auto';
  }

  function addMessage(role, text) {
    const element = document.createElement('div');
    element.className = `meem-assistant-msg ${role}`;
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
    positionPanel();
    setTimeout(() => { positionPanel(); input.focus(); }, 60);
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
      const message = status === 401
        ? 'يرجى تسجيل الدخول أولاً حتى أتمكن من الوصول إلى بيانات طلباتك.'
        : status === 429
          ? 'وصلت للحد المؤقت من الرسائل. انتظر عدة دقائق ثم حاول مرة أخرى.'
          : status === 413
            ? 'الرسالة طويلة جداً. اختصرها ثم أعد الإرسال.'
            : 'تعذر الاتصال بالمساعد حالياً. حاول مرة أخرى بعد قليل أو تواصل مع الدعم.';
      addMessage('assistant', message);
    } finally {
      send.disabled = false;
      typing.hidden = true;
      input.focus();
    }
  }

  toggle.addEventListener('click', () => {
    if (suppressToggle) return;
    panel.classList.contains('is-open') ? closePanel() : openPanel();
  });
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

  restorePosition();
})();
