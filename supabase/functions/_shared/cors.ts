// ============================================================================
// MEEM STORE — منطق CORS موحّد لدوال الـEdge
// ----------------------------------------------------------------------------
// العقد:
//   • الأصل المسموح به يُحدَّد من: (1) قائمة أصول صريحة من env، (2) دومين الإنتاج،
//     (3) نمط دقيق لروابط المعاينة (regex مُقيَّد).
//   • لا يُستعمل أي نمط مفتوح (لا "*"، ولا سماح لأي *.vercel.app عام).
//   • يُعاد أصل الطلب فقط إذا طابق؛ وإلا يُعاد دومين الإنتاج (فيرفضه المتصفح).
// هذا الملف نقي (بلا Deno/imports) حتى يُختبر من Node مباشرة.
// ============================================================================

export type OriginConfig = {
  requestOrigin: string;
  configured: string;
  previewRegex: string;
  productionOrigin: string;
};

// النمط الافتراضي: روابط معاينة مشروعنا فقط، https، بلا مسارات، ولقطة واحدة.
//   https://raizey-store-qw.vercel.app            (الإنتاج)
//   https://raizey-store-qw-git-branch-team.vercel.app  (معاينة)
export const DEFAULT_PREVIEW_ORIGIN_REGEX =
  "^https:\\/\\/raizey-store-qw(?:-[a-z0-9-]+)?\\.vercel\\.app$";

export function isPreviewOrigin(origin: string, pattern: string): boolean {
  if (!origin || !pattern) return false;
  let re: RegExp;
  try {
    re = new RegExp(pattern);
  } catch {
    return false;
  }
  return re.test(origin);
}

export function configuredOrigins(configured: string): string[] {
  if (!configured || configured === "*") return [];
  return configured
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
}

export function resolveAllowedOrigin(config: OriginConfig): string {
  const allowlist = [...configuredOrigins(config.configured), config.productionOrigin].filter(Boolean);
  const requestOrigin = config.requestOrigin || "";
  if (requestOrigin && allowlist.includes(requestOrigin)) return requestOrigin;
  if (requestOrigin && isPreviewOrigin(requestOrigin, config.previewRegex)) return requestOrigin;
  return config.productionOrigin || allowlist[0] || "";
}

export function buildCorsHeaders(origin: string): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}
