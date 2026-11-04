import { createTelegramAdminHandler } from "./handler.ts";

const env = (name: string) => (Deno.env.get(name) || "").trim();
function databaseKey(): string {
  try {
    const keys = JSON.parse(env("SUPABASE_SECRET_KEYS") || "{}");
    if (typeof keys.telegram === "string") return keys.telegram;
    if (typeof keys.default === "string") return keys.default;
  } catch { /* Legacy projects still supply the server-only service-role key. */ }
  return env("SUPABASE_SERVICE_ROLE_KEY");
}

Deno.serve(createTelegramAdminHandler({
  botToken: env("TELEGRAM_BOT_TOKEN"),
  webhookSecret: env("TELEGRAM_WEBHOOK_SECRET"),
  ownerId: env("TELEGRAM_OWNER_ID"),
}, {
  async probeDatabase() {
    const url = new URL(env("SUPABASE_URL"));
    if (url.protocol !== "https:" || !url.hostname.endsWith(".supabase.co")) throw new Error("invalid_project");
    url.pathname = "/rest/v1/orders";
    url.search = "select=id&limit=1";
    const key = databaseKey();
    if (!key) throw new Error("missing_database_key");
    const headers: Record<string, string> = { apikey: key };
    if (!key.startsWith("sb_secret_")) headers.Authorization = `Bearer ${key}`;
    // HEAD checks access to the actual orders table without downloading PII.
    const response = await fetch(url, { method: "HEAD", headers, signal: AbortSignal.timeout(8_000) });
    if (!response.ok) throw new Error("database_unavailable");
  },
}));
