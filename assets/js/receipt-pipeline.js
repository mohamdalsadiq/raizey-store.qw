/*
 * MEEM STORE — Server-only receipt verification pipeline.
 * OCR, hashing and financial decisions stay inside the authenticated
 * Supabase Edge Function. The browser only prepares the image and displays
 * the returned result.
 */
(function (root) {
  'use strict';

  const FALLBACK_FLAGS = [
    'server_ocr_failed', 'server_ocr_timeout', 'server_rate_limited',
    'auth_required', 'judge_error', 'missing_image', 'image_too_large',
    'invalid_image_type', 'receipt_processing_failed',
    'receipt_consent_required', 'receipt_provider_review_pending'
  ];
  const MAX_DIMENSION = 1600;
  const JPEG_QUALITY = 0.85;
  const COMPRESS_ABOVE_BYTES = 900 * 1024;
  const MAX_UPLOAD_BYTES = 5 * 1024 * 1024;
  const ALLOWED_IMAGE_TYPES = new Set(['image/jpeg', 'image/jpg', 'image/png', 'image/webp']);
  const EDGE_TIMEOUT_MS = 160000;
  const QUEUE_WAIT_MS = 14 * 60 * 1000;

  // Shared, indeterminate feedback. No invented percentage or completion time.
  // Caller guards own the scan; this helper only locks controls and renders UI.
  function beginScanActivity(status, controls) {
    const locked = [...new Set((controls || []).filter(Boolean))].map(el => {
      const saved = {el, disabled: typeof el.disabled === 'boolean' ? el.disabled : null,
        aria: el.getAttribute('aria-disabled'), locked: el.classList.contains('receipt-scan-locked')};
      if (saved.disabled !== null) el.disabled = true;
      el.setAttribute('aria-disabled', 'true');
      el.classList.add('receipt-scan-locked');
      return saved;
    });
    const doc = root.document;
    let copy = null, message = null, finished = false;
    if (status && doc) {
      const orbit = doc.createElement('span');
      orbit.className = 'receipt-scan-orbit'; orbit.setAttribute('aria-hidden', 'true');
      copy = doc.createElement('div'); copy.className = 'receipt-scan-copy';
      const title = doc.createElement('strong'); title.textContent = 'جارٍ فحص إشعار التحويل';
      message = doc.createElement('p'); message.textContent = 'نقرأ الصورة ونتحقق من بيانات التحويل. ستظهر النتيجة هنا.';
      copy.append(title, message);
      const track = doc.createElement('span'); track.className = 'receipt-scan-track'; track.setAttribute('aria-hidden', 'true');
      status.replaceChildren(orbit, copy, track);
      status.classList.add('receipt-scan-busy');
      status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite'); status.setAttribute('aria-busy', 'true');
    }
    return {
      update(text) { if (!finished && message && status.contains(copy)) message.textContent = String(text || 'جارٍ فحص الصورة…'); },
      finish() {
        if (finished) return;
        finished = true;
        for (const saved of locked) {
          if (saved.disabled !== null) saved.el.disabled = saved.disabled;
          if (saved.aria === null) saved.el.removeAttribute('aria-disabled'); else saved.el.setAttribute('aria-disabled', saved.aria);
          if (!saved.locked) saved.el.classList.remove('receipt-scan-locked');
        }
        if (status) {
          if (copy && status.contains(copy)) status.replaceChildren();
          status.classList.remove('receipt-scan-busy'); status.setAttribute('aria-busy', 'false');
        }
      }
    };
  }

  function validateImageFile(file) {
    if (!file || !(file instanceof Blob)) throw new Error('missing_image');
    const mimeType = String(file.type || '').toLowerCase();
    if (!ALLOWED_IMAGE_TYPES.has(mimeType)) throw new Error('invalid_image_type');
    if (file.size <= 0 || file.size > MAX_UPLOAD_BYTES) throw new Error('image_too_large');
    return true;
  }

  function normalizeRef(value) {
    return String(value || '')
      .replace(/[\u0660-\u0669]/g, (digit) => String(digit.charCodeAt(0) - 0x0660))
      .replace(/[\u06F0-\u06F9]/g, (digit) => String(digit.charCodeAt(0) - 0x06F0))
      .toUpperCase()
      .replace(/[^A-Z0-9]/g, '');
  }

  async function getAccessToken() {
    if (!root.supabaseClient || !root.supabaseClient.auth) throw new Error('supabase_client_missing');
    const { data, error } = await root.supabaseClient.auth.getSession();
    if (error || !data?.session?.access_token) throw new Error('auth_required');
    return data.session.access_token;
  }

  function fileToBase64(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => {
        const value = String(reader.result || '');
        const comma = value.indexOf(',');
        resolve(comma >= 0 ? value.slice(comma + 1) : value);
      };
      reader.onerror = () => reject(reader.error || new Error('file_read_error'));
      reader.readAsDataURL(file);
    });
  }

  function compressForServer(file) {
    return new Promise((resolve) => {
      if (!file || file.size <= COMPRESS_ABOVE_BYTES) {
        resolve({ base64: null, mimeType: (file && file.type) || 'image/jpeg' });
        return;
      }
      let settled = false;
      const url = URL.createObjectURL(file);
      const img = new Image();
      let timer;
      const finish = (value) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        URL.revokeObjectURL(url);
        resolve(value);
      };
      timer = setTimeout(() => finish({ base64: null, mimeType: file.type || 'image/jpeg' }), 9000);
      img.onerror = () => finish({ base64: null, mimeType: file.type || 'image/jpeg' });
      img.onload = () => {
        try {
          const width = img.naturalWidth;
          const height = img.naturalHeight;
          const scale = Math.min(1, MAX_DIMENSION / Math.max(width, height));
          const canvas = document.createElement('canvas');
          canvas.width = Math.max(1, Math.round(width * scale));
          canvas.height = Math.max(1, Math.round(height * scale));
          const context = canvas.getContext('2d');
          context.imageSmoothingQuality = 'high';
          context.drawImage(img, 0, 0, canvas.width, canvas.height);
          const dataUrl = canvas.toDataURL('image/jpeg', JPEG_QUALITY);
          const comma = dataUrl.indexOf(',');
          finish({
            base64: comma >= 0 ? dataUrl.slice(comma + 1) : null,
            mimeType: 'image/jpeg'
          });
        } catch (_) {
          finish({ base64: null, mimeType: file.type || 'image/jpeg' });
        }
      };
      img.src = url;
    });
  }

  async function serverVerify(file, options, extraFile) {
    const opts = options || {};
    validateImageFile(file);
    if (opts.manualOnly === true) throw new Error('automatic_check_required');
    if (extraFile) throw new Error('use_one_complete_receipt');
    const compressed = await compressForServer(file);
    const imageBase64 = compressed.base64 || await fileToBase64(file);
    const token = await getAccessToken();
    const endpoint = `${String(root.SUPABASE_URL || '').replace(/\/$/, '')}/functions/v1/process-receipt`;
    if (!endpoint.startsWith('https://')) throw new Error('supabase_endpoint_missing');

    const controller = new AbortController();
    const processingMs = Number(opts.serverTimeoutMs || EDGE_TIMEOUT_MS);
    const queueMs = opts.serverTimeoutMs ? processingMs : QUEUE_WAIT_MS;
    let timer;
    const arm = ms => { clearTimeout(timer); timer = setTimeout(() => controller.abort(), Math.max(1,ms)); };
    arm(processingMs);
    const headers = {'Content-Type':'application/json','Authorization':`Bearer ${token}`,
      ...(root.SUPABASE_ANON_KEY ? {apikey:root.SUPABASE_ANON_KEY} : {})};
    const body={imageBase64,mimeType:compressed.mimeType || file.type || 'image/jpeg',
      expectedAmount:opts.expectedAmount,manualRef:opts.manualRef,expectedAccount:opts.expectedAccount,expectedMethodId:opts.expectedMethodId || null};
    const send=async(url,payload)=>{
      // A queued page can outlive its original access token; use the SDK's
      // current session on every request without exposing it to the UI.
      headers.Authorization=`Bearer ${await getAccessToken()}`;
      const response=await fetch(url,{method:'POST',headers,body:JSON.stringify(payload),signal:controller.signal});
      let data=null;try{data=await response.json();}catch(_){}
      if(['receipt_consent_required','receipt_provider_review_pending'].includes(data?.error)) {
        if(data.error==='receipt_consent_required') root.MeemReceiptConsent?.invalidate?.();
        const failure=new Error(data.error);failure.serverMessage=data.message;throw failure;
      }
      if(response.status===401 || response.status===403) throw new Error('auth_required');
      if(response.status===429) throw new Error('server_rate_limited');
      if(!response.ok || !data || data.ok===false){const e=new Error(data?.error || `server_http_${response.status}`);e.serverMessage=data?.message;throw e;}
      return data;
    };
    const pause=(ms)=>new Promise((resolve,reject)=>{
      const stop=()=>{clearTimeout(t);reject(Object.assign(new Error('aborted'),{name:'AbortError'}));};
      const t=setTimeout(()=>{controller.signal.removeEventListener('abort',stop);resolve();},ms);
      if(controller.signal.aborted) stop(); else controller.signal.addEventListener('abort',stop,{once:true});
    });
    try {
      let data=await send(endpoint,body);
      const queuedAt=Date.now();
      while(data.queue && Date.now()-queuedAt<queueMs){
        arm(queueMs-(Date.now()-queuedAt));
        const queue=data.queue;
        if(!/^[0-9a-f-]{36}$/i.test(String(queue.ticketId || ''))) throw new Error('invalid_queue_ticket');
        if(typeof opts.onStatus==='function')opts.onStatus(`الإيصال في انتظار الدور — موضعك: ${Number(queue.position)||1}.`);
        await pause(Math.min(5000,Math.max(1000,Number(queue.retryAfter||3)*1000)));
        const polled=await send(endpoint+'?operation=poll',{ticketId:queue.ticketId});
        if(polled.queue?.canRetry){arm(processingMs);data=await send(endpoint,body);}else data=polled;
      }
      if(data.queue) data.message='الفحص ما زال في انتظار الدور. أعد تجهيز نفس الإيصال بعد قليل؛ لم تُستهلك حصة فحص مكتمل ولم يُنشأ طلب.';
      if ((data.decision === 'accept' || data.decision === 'review_admin') && data.submissionAllowed !== true) throw new Error('server_scan_contract_invalid');
      if (data.submissionAllowed === true && (!data.receiptHash || !data.receiptPath || !data.attachmentId || !data.scanId || data.receiptPolicy !== 'mandatory-visual-v1' || data.automaticCheckComplete !== true)) throw new Error('server_scan_contract_invalid');
      const u=data.usage;
      if(u && Number.isInteger(u.remaining) && Number.isInteger(u.dailyLimit)){
        data.message=(data.message || '')+` المتبقي اليوم: ${u.remaining} من ${u.dailyLimit}؛ تتجدد الحصة منتصف الليل بتوقيت السودان.`;
        if(u.suspended) data.message+=' ميزة الفحص مجمدة حتى مراجعة الإدارة.';
        else if(Number(u.violations)>0) data.message+=` تحذير إساءة استخدام: ${u.violations} من ${u.violationLimit}. ارفع إشعار تحويل فقط.`;
      }
      return data;
    } finally {
      clearTimeout(timer);
    }
  }

  function softReview(flag, message) {
    return {
      decision: 'review',
      submissionAllowed: false,
      ocrStatus: 'needs_review',
      message: message || 'تعذّر إكمال الفحص الخادمي. لم يُنشأ أي طلب؛ أعد المحاولة بعد لحظات.',
      riskFlags: [flag], confidence: null, provider: null, providerName: null,
      language: null, passes: 0, textLength: 0, version: 4,
      source: 'edge-client',
      extracted: { txRef: null, amount: null, dateTime: null },
      refVerified: false, amountVerified: false
    };
  }

  async function analyze(file, options) {
    const opts = options || {};
    const onStatus = typeof opts.onStatus === 'function' ? opts.onStatus : () => {};
    try {
      onStatus('جارِ إرسال الإيصال للفحص الآمن على الخادم...');
      const result = await serverVerify(file, opts, opts.extraFile || null);
      onStatus(result.queue ? 'الفحص في انتظار توفر السعة.' : 'تمت معالجة طلب الفحص.');
      return result;
    } catch (error) {
      if (typeof opts.onServerError === 'function') opts.onServerError(error);
      const errorCode = String(error && error.message || '');
      const flag = ['receipt_consent_required','receipt_provider_review_pending'].includes(errorCode) ? errorCode : error && error.name === 'AbortError'
        ? 'server_ocr_timeout'
        : errorCode.includes('auth_required')
          ? 'auth_required'
          : errorCode === 'server_rate_limited'
            ? 'server_rate_limited'
            : errorCode === 'image_too_large'
              ? 'image_too_large'
              : errorCode === 'invalid_image_type'
                ? 'invalid_image_type'
                : 'server_ocr_failed';
      const message = error && error.serverMessage
        ? error.serverMessage
        : flag === 'server_rate_limited'
          ? 'تم تجاوز عدد محاولات الفحص مؤقتاً. انتظر قليلًا ثم أعد المحاولة.'
          : flag === 'image_too_large'
            ? 'حجم الصورة أكبر من 5 ميجابايت. ارفع JPG أو PNG أو WEBP أصغر.'
            : flag === 'invalid_image_type'
              ? 'صيغة الصورة غير مدعومة. استخدم JPG أو PNG أو WEBP.'
              : undefined;
      return softReview(flag, message);
    }
  }

  root.MeemReceiptPipeline = {
    beginScanActivity,
    fileToBase64,
    validateImageFile,
    compressForServer,
    normalizeRef,
    serverVerify,
    analyze,
    softReview,
    fallbackFlags: FALLBACK_FLAGS.slice()
  };
})(window);
