import { createTelegramAdminHandler } from "./handler.ts";
import { createConfigLoader } from "./config.ts";

const env = (name: string) => (Deno.env.get(name) || "").trim();
function databaseKey(): string {
  try {
    const keys = JSON.parse(env("SUPABASE_SECRET_KEYS") || "{}");
    if (typeof keys.telegram === "string") return keys.telegram;
    if (typeof keys.default === "string") return keys.default;
  } catch { /* Legacy projects still supply the server-only service-role key. */ }
  return env("SUPABASE_SERVICE_ROLE_KEY");
}

function databaseHeaders(): Record<string, string> {
  const key = databaseKey();
  if (!key) throw new Error("missing_database_key");
  const headers: Record<string, string> = { apikey: key };
  if (!key.startsWith("sb_secret_")) headers.Authorization = `Bearer ${key}`;
  return headers;
}

function databaseURL(path: string): URL {
  const url = new URL(env("SUPABASE_URL"));
  if (url.protocol !== "https:" || !url.hostname.endsWith(".supabase.co")) throw new Error("invalid_project");
  url.pathname = path;
  return url;
}

const loadConfiguration = createConfigLoader({
  botToken: env("TELEGRAM_BOT_TOKEN"),
  webhookSecret: env("TELEGRAM_WEBHOOK_SECRET"),
  ownerId: env("TELEGRAM_OWNER_ID"),
}, async () => {
  const response = await fetch(databaseURL("/rest/v1/rpc/telegram_admin_configuration"), {
    method: "POST", headers: { ...databaseHeaders(), "Content-Type": "application/json" },
    body: "{}", signal: AbortSignal.timeout(8_000),
  });
  if (!response.ok) throw new Error("configuration_unavailable");
  return await response.json();
});

const dependencies = {
  async probeDatabase() {
    const url = databaseURL("/rest/v1/orders");
    url.search = "select=id&limit=1";
    // HEAD checks access to the actual orders table without downloading PII.
    const response = await fetch(url, { method: "HEAD", headers: databaseHeaders(), signal: AbortSignal.timeout(8_000) });
    if (!response.ok) throw new Error("database_unavailable");
  },
};

Deno.serve(async (request: Request) => {
  // Reject malformed or unauthenticated requests before querying Vault.
  if (request.method !== "POST") return new Response(null, { status: 405, headers: { "Allow": "POST" } });
  const secret = request.headers.get("X-Telegram-Bot-Api-Secret-Token") || "";
  if (!/^[A-Za-z0-9_-]{32,256}$/.test(secret)) {
    return Response.json({ error: "unauthorized" }, { status: 401, headers: { "Cache-Control": "no-store" } });
  }
  let config;
  try { config = await loadConfiguration(); } catch {
    return Response.json({ error: "integration_not_configured" }, { status: 503, headers: { "Cache-Control": "no-store" } });
  }
  return await createTelegramAdminHandler(config, dependencies)(request);
});
