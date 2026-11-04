import { readBoundedJson } from "../_shared/request-body.ts";

type Config = { botToken: string; webhookSecret: string; ownerId: string };
type Dependencies = { probeDatabase: () => Promise<void>; fetch?: typeof fetch };
type Message = { chat?: { id?: number; type?: string }; from?: { id?: number; is_bot?: boolean }; sender_chat?: unknown; text?: string };
type Update = { update_id?: number; message?: Message; callback_query?: { id?: string; from?: { id?: number; is_bot?: boolean }; message?: Message; data?: string } };

function json(status: number, body: object): Response {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" } });
}

async function sameSecret(a: string, b: string): Promise<boolean> {
  const hash = (s: string) => crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  const [left, right] = await Promise.all([hash(a), hash(b)]);
  const x = new Uint8Array(left), y = new Uint8Array(right);
  let different = 0;
  for (let i = 0; i < x.length; i++) different |= x[i] ^ y[i];
  return different === 0;
}

// Phase 1 is intentionally read-only: no order, receipt or wallet mutations.
// Group delivery and order actions will be added only after this probe passes.
export function createTelegramAdminHandler(config: Config, dependencies: Dependencies) {
  const http = dependencies.fetch ?? fetch;
  const ready = /^[1-9]\d{0,15}$/.test(config.ownerId)
    && Number.isSafeInteger(Number(config.ownerId))
    && /^\d+:[A-Za-z0-9_-]{20,}$/.test(config.botToken)
    && /^[A-Za-z0-9_-]{32,256}$/.test(config.webhookSecret);

  async function telegram(method: string, body: object) {
    const result = await http(`https://api.telegram.org/bot${config.botToken}/${method}`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body), signal: AbortSignal.timeout(8_000),
    });
    if (!result.ok || (await result.json()).ok !== true) throw new Error("telegram_unavailable");
  }

  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
    if (!ready) return json(503, { error: "integration_not_configured" });
    const suppliedSecret = request.headers.get("X-Telegram-Bot-Api-Secret-Token") || "";
    if (suppliedSecret.length > 256 || !await sameSecret(suppliedSecret, config.webhookSecret)) {
      return json(401, { error: "unauthorized" });
    }
    if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
      return json(415, { error: "unsupported_media_type" });
    }
    let update: Update;
    try {
      update = await readBoundedJson(request, 16 * 1024) as Update;
      if (!update || typeof update !== "object" || !Number.isSafeInteger(update.update_id)) throw new Error("invalid_json");
    } catch (error) {
      return json(error instanceof Error && error.message === "payload_too_large" ? 413 : 400, { error: "invalid_update" });
    }
    const callback = update.callback_query;
    const message = callback?.message ?? update.message;
    const actor = callback?.from ?? message?.from;
    // Numeric identity and private-chat binding are both required. A username,
    // forwarded message, group admin title or callback payload grants no access.
    if (!actor || actor.is_bot || !Number.isSafeInteger(actor.id) || String(actor.id) !== config.ownerId
      || message?.chat?.type !== "private" || !Number.isSafeInteger(message.chat.id) || String(message.chat.id) !== config.ownerId
      || message.sender_chat) return json(200, { ok: true });

    const command = callback ? callback.data : message.text?.trim();
    if (!["/start", "/test", "connection:test"].includes(command || "")) return json(200, { ok: true });

    try {
      if (callback?.id) await telegram("answerCallbackQuery", { callback_query_id: callback.id });
      let text = "MEEM STORE 💙\nمساعد إدارة المتجر — اختبار الاتصال\nاضغط الزر لفحص اتصال قاعدة بيانات المتجر.";
      if (command !== "/start") {
        try {
          await dependencies.probeDatabase();
          text = "✅ نجح اختبار الربط\nتلجرام ↔ خادم المتجر ↔ قاعدة بيانات الطلبات\nهذا اختبار قراءة فقط؛ لم يتم تعديل أي طلب أو رصيد.";
        } catch {
          text = "⚠️ البوت يستقبل أوامرك، لكن فحص قاعدة البيانات لم ينجح.\nلم يتم تعديل أي طلب. راجع إعدادات الاتصال ثم أعد الاختبار.";
        }
      }
      await telegram("sendMessage", {
        chat_id: Number(config.ownerId), text, protect_content: true,
        reply_markup: { inline_keyboard: [[{ text: "🔌 فحص الربط بالمتجر", callback_data: "connection:test" }]] },
      });
      return json(200, { ok: true });
    } catch {
      // Never log bot-token URLs, incoming updates or upstream response bodies.
      return json(502, { error: "delivery_failed" });
    }
  };
}
