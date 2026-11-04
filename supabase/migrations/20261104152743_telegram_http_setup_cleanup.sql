-- HTTP was used for one-time Telegram setup and diagnostics only.
-- Remove its SQL networking surface once provisioning is complete.
DROP EXTENSION IF EXISTS http;
