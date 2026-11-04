BEGIN;

-- The definer lives outside the exposed API schema and only reads three named
-- Vault entries. No client, administrator JWT or anonymous session can call it.
CREATE OR REPLACE FUNCTION private.meem_telegram_configuration()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF pg_catalog.current_setting('role', true) IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;
  RETURN (
    SELECT pg_catalog.jsonb_build_object(
      'botToken', COALESCE(max(decrypted_secret) FILTER (WHERE name = 'meem_telegram_bot_token'), ''),
      'webhookSecret', COALESCE(max(decrypted_secret) FILTER (WHERE name = 'meem_telegram_webhook_secret'), ''),
      'ownerId', COALESCE(max(decrypted_secret) FILTER (WHERE name = 'meem_telegram_owner_id'), '')
    )
    FROM vault.decrypted_secrets
    WHERE name IN ('meem_telegram_bot_token', 'meem_telegram_webhook_secret', 'meem_telegram_owner_id')
  );
END;
$function$;

REVOKE ALL ON FUNCTION private.meem_telegram_configuration() FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA private TO service_role;
GRANT EXECUTE ON FUNCTION private.meem_telegram_configuration() TO service_role;

-- PostgREST wrapper has no elevated privileges; the service key must be valid.
CREATE OR REPLACE FUNCTION public.telegram_admin_configuration()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT private.meem_telegram_configuration();
$function$;
REVOKE ALL ON FUNCTION public.telegram_admin_configuration() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.telegram_admin_configuration() TO service_role;

NOTIFY pgrst, 'reload schema';
COMMIT;
