export type TelegramConfig = { botToken: string; webhookSecret: string; ownerId: string };

// Environment secrets still work. Vault is used when dashboard secret management
// is unavailable. The RPC is executable by service_role only, never by browsers.
export function createConfigLoader(
  environment: TelegramConfig,
  loadVault: () => Promise<unknown>,
  clock: () => number = Date.now,
) {
  let cached: TelegramConfig | undefined;
  let expiresAt = 0;
  let pending: Promise<TelegramConfig> | undefined;
  return async (): Promise<TelegramConfig> => {
    if (environment.botToken && environment.webhookSecret && environment.ownerId) return environment;
    if (cached && clock() < expiresAt) return cached;
    if (pending) return pending;
    pending = (async () => {
      const raw = await loadVault();
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("configuration_unavailable");
      const input = raw as Record<string, unknown>;
      const value = (key: string) => typeof input[key] === "string" ? input[key].trim() : "";
      cached = {
        botToken: environment.botToken || value("botToken"),
        webhookSecret: environment.webhookSecret || value("webhookSecret"),
        ownerId: environment.ownerId || value("ownerId"),
      };
      expiresAt = clock() + 30_000;
      return cached;
    })();
    try { return await pending; } finally { pending = undefined; }
  };
}
