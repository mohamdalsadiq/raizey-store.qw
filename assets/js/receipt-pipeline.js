/*
 * RAIZEY STORE — Unified receipt verification pipeline
 * Server-first verification with a deterministic browser fallback.
 * Used by wallet topups and checkout so both flows share one contract.
 */
(function (root) {
  'use strict';

  const FALLBACK_FLAGS = [
    'gemini_not_configured', 'server_ocr_failed', 'server_ocr_timeout',
    'judge_error', 'missing_image', 'image_too_large', 'method_not_allowed'
  ];
  const MAX_DIMENSION = 1600;
  const JPEG_QUALITY = 0.85;
  const COMPRESS_ABOVE_BYTES = 900 * 1024;

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
    const compressed = await compressForServer(file);
    const imageBase64 = compressed.base64 || await fileToBase64(file);
    let imageBase64Extra = null;
    let mimeTypeExtra = null;
    if (extraFile) {
      const compressedExtra = await compressForServer(extraFile);
      imageBase64Extra = compressedExtra.base64 || await fileToBase64(extraFile);
      mimeTypeExtra = compressedExtra.mimeType || extraFile.type || 'image/jpeg';
    }
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), Number(opts.serverTimeoutMs || 32000));
    try {
      const response = await fetch('/api/verify-receipt', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
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
      if (response.status === 404) throw new Error('server_not_deployed');
      if (!response.ok) throw new Error('server_http_' + response.status);
      const data = await response.json();
      if (Array.isArray(data && data.riskFlags) && data.riskFlags.some((flag) => FALLBACK_FLAGS.includes(flag))) {
        const error = new Error('server_needs_fallback:' + data.riskFlags[0]);
        error.serverDebug = data.debug || null;
        throw error;
      }
      return data;
    } finally {
      clearTimeout(timer);
    }
  }

  function softReview(flag) {
    return {
      decision: 'review',
      ocrStatus: 'needs_review',
      message: 'تعذّر إكمال الفحص الآلي للصورة. تم استلام الإيصال وسيُراجع يدوياً من الإدارة.',
      riskFlags: [flag], confidence: null, provider: null, providerName: null,
      language: null, passes: 0, textLength: 0, version: 3,
      extracted: { txRef: null, amount: null, dateTime: null },
      refVerified: false, amountVerified: false
    };
  }

  async function analyze(file, options) {
    const opts = options || {};
    const onStatus = typeof opts.onStatus === 'function' ? opts.onStatus : () => {};
    try {
      onStatus('جارِ فحص الصورة عبر الخادم...');
      return await serverVerify(file, opts, opts.extraFile || null);
    } catch (serverError) {
      if (typeof opts.onServerError === 'function') opts.onServerError(serverError);
    }

    if (root.ReceiptIntel && typeof root.ReceiptIntel.analyze === 'function') {
      try {
        onStatus('جارِ تشغيل الفحص الاحتياطي على الجهاز...');
        return await root.ReceiptIntel.analyze(file, {
          expectedAmount: opts.expectedAmount,
          manualRef: opts.manualRef,
          expectedAccount: opts.expectedAccount,
          onStatus
        });
      } catch (clientError) {
        if (typeof opts.onClientError === 'function') opts.onClientError(clientError);
        return softReview('scan_error');
      }
    }
    return softReview('engine_missing');
  }

  root.RaizeyReceiptPipeline = {
    fileToBase64,
    compressForServer,
    serverVerify,
    analyze,
    softReview,
    fallbackFlags: FALLBACK_FLAGS.slice()
  };
})(window);
