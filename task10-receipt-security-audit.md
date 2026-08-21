## client receipt pipeline
2: * RAIZEY STORE — Server-only receipt verification pipeline
5: * وإرسالها إلى Supabase Edge Function process-receipt وانتظار النتيجة.
10:  const MAX_DIMENSION = 1600;
11:  const JPEG_QUALITY = 0.85;
17:    'invalid_base64', 'receipt_processing_failed'
35:      if (!file || file.size <= COMPRESS_ABOVE_BYTES) {
36:        resolve({ base64: null, mimeType: (file && file.type) || 'image/jpeg' });
50:      timer = setTimeout(() => finish({ base64: null, mimeType: file.type || 'image/jpeg' }), 9000);
51:      img.onerror = () => finish({ base64: null, mimeType: file.type || 'image/jpeg' });
56:          const scale = Math.min(1, MAX_DIMENSION / Math.max(width, height));
64:          const dataUrl = canvas.toDataURL('image/jpeg', JPEG_QUALITY);
66:          finish({ base64: comma >= 0 ? dataUrl.slice(comma + 1) : null, mimeType: 'image/jpeg' });
68:          finish({ base64: null, mimeType: file.type || 'image/jpeg' });
121:      mimeTypeExtra = compressedExtra.mimeType || extraFile.type || 'image/jpeg';
125:    const endpoint = `${String(root.SUPABASE_URL || '').replace(/\/$/, '')}/functions/v1/process-receipt`;
140:          mimeType: compressed.mimeType || file.type || 'image/jpeg',
158:      if (!data.scanId || !data.receiptHash) throw new Error('server_scan_contract_invalid');
167:    const onStatus = typeof opts.onStatus === 'function' ? opts.onStatus : () => {};
174:      if (typeof opts.onServerError === 'function') opts.onServerError(error);

## edge validation
6:const GEMINI_MODELS = [
11:const GEMINI_TIMEOUT_MS = 24_000;
19:  "image/jpeg",
20:  "image/png",
21:  "image/webp",
22:  "image/heic",
23:  "image/heif",
70:    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
99:  let mime = String(value || "image/jpeg").toLowerCase().split(";")[0].trim();
100:  if (mime === "image/jpg") mime = "image/jpeg";
147:  }), GEMINI_TIMEOUT_MS, "gemini_request");
176:  for (const model of GEMINI_MODELS) {
204:  }), GEMINI_TIMEOUT_MS, "gemini_json");
215:  for (const model of GEMINI_MODELS) {
232:  const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
233:  if (!url || !serviceKey) throw new Error("supabase_service_credentials_missing");
234:  return createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
261:    tx_ref_ocr: extracted.txRef || null,
317:  const apiKey = env("GEMINI_API_KEY");
345:      return { ...rejected, scanId: scan.id, receiptHash: hash, expiresAt: scan.expires_at };
354:    return { ...technical, scanId: scan.id, receiptHash: hash, expiresAt: scan.expires_at };
408:  return { ...result, scanId: scan.id, receiptHash: hash, expiresAt: scan.expires_at };

## public secrets
./supabase/functions/process-receipt/README.md:9:`SUPABASE_URL` و`SUPABASE_SERVICE_ROLE_KEY` متاحان تلقائيًا داخل بيئة Edge Function. يجب ضبط السر التالي في Supabase Dashboard ضمن Function Secrets:
./supabase/functions/process-receipt/README.md:12:GEMINI_API_KEY=<قيمة مفتاح Gemini في بيئة Supabase فقط>
./task10-audit-findings.md:281:./supabase/functions/process-receipt/index.ts:232:  const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
./task10-audit-findings.md:282:./supabase/functions/process-receipt/index.ts:317:  const apiKey = env("GEMINI_API_KEY");
./task10-supabase-local-security-audit.md:180:./supabase-critical-fixes-7.sql:472:GRANT ALL ON public.payment_codes TO service_role;
./task10-receipt-security-audit.md:37:232:  const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
./task10-receipt-security-audit.md:41:317:  const apiKey = env("GEMINI_API_KEY");

## Deployment note

The local receipt contract patch is tested, but Supabase MCP and session connector access returned `403 Forbidden` during this run. No Supabase schema or Edge Function deployment was attempted after that failure, so production `process-receipt` must be checked/deployed through the Supabase Dashboard or after connector re-authentication before relying on the new 5MB contract in production.
