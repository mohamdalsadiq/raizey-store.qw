/*
 * RAIZEY STORE — Server-only receipt verification pipeline.
 * OCR, hashing and financial decisions stay inside the authenticated
 * Supabase Edge Function. The browser only prepares the image and displays
 * the returned result.
 */
(function (root) {
  'use strict';

  const FALLBACK_FLAGS = [
    'server_ocr_failed', 'server_ocr_timeout', 'server_rate_limited',
    'auth_required', 'judge_error', 'missing_image', 'image_too_large',
    'invalid_image_type', 'receipt_processing_failed'
  ];
  const MAX_DIMENSION = 1600;
  const JPEG_QUALITY = 0.85;
  const COMPRESS_ABOVE_BYTES = 900 * 1024;
  const MAX_UPLOAD_BYTES = 5 * 1024 * 1024;
  const ALLOWED_IMAGE_TYPES = new Set(['image/jpeg', 'image/jpg', 'image/png', 'image/webp']);
  const EDGE_TIMEOUT_MS = 100000;

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
    if (extraFile) validateImageFile(extraFile);
    const compressed = await compressForServer(file);
    const imageBase64 = compressed.base64 || await fileToBase64(file);
    let imageBase64Extra = null;
    let mimeTypeExtra = null;
    if (extraFile) {
      const compressedExtra = await compressForServer(extraFile);
      imageBase64Extra = compressedExtra.base64 || await fileToBase64(extraFile);
      mimeTypeExtra = compressedExtra.mimeType || extraFile.type || 'image/jpeg';
    }
    const token = await getAccessToken();
    const endpoint = `${String(root.SUPABASE_URL || '').replace(/\/$/, '')}/functions/v1/process-receipt`;
    if (!endpoint.startsWith('https://')) throw new Error('supabase_endpoint_missing');

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), Number(opts.serverTimeoutMs || EDGE_TIMEOUT_MS));
    try {
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
          ...(root.SUPABASE_ANON_KEY ? { apikey: root.SUPABASE_ANON_KEY } : {})
        },
        body: JSON.stringify({
          imageBase64,
          mimeType: compressed.mimeType || file.type || 'image/jpeg',
          imageBase64Extra,
          mimeTypeExtra,
          expectedAmount: opts.expectedAmount,
          manualRef: opts.manualRef,
          expectedAccount: opts.expectedAccount
        }),
        signal: controller.signal
      });
      let data = null;
      try { data = await response.json(); } catch (_) {}
      if (response.status === 401 || response.status === 403) throw new Error('auth_required');
      if (response.status === 429) throw new Error('server_rate_limited');
      if (!response.ok || !data || data.ok === false) {
        const error = new Error((data && data.error) || `server_http_${response.status}`);
        error.serverMessage = data && data.message;
        throw error;
      }
      if (!data.scanId || !data.receiptHash) throw new Error('server_scan_contract_invalid');
      return data;
    } finally {
      clearTimeout(timer);
    }
  }

  function softReview(flag, message) {
    return {
      decision: 'review',
      ocrStatus: 'needs_review',
      message: message || 'تعذّر إكمال الفحص الخادمي. لم يُنشأ أي طلب؛ أعد المحاولة بعد لحظات.',
      riskFlags: [flag], confidence: null, provider: null, providerName: null,
      language: null, passes: 0, textLength: 0, version: 4,
      source: 'edge-client', submissionAllowed: false,
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
      onStatus('اكتمل الفحص الخادمي.');
      return result;
    } catch (error) {
      if (typeof opts.onServerError === 'function') opts.onServerError(error);
      const errorCode = String(error && error.message || '');
      const flag = error && error.name === 'AbortError'
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

  root.RaizeyReceiptPipeline = {
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
