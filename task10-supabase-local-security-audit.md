## Supabase config
# RAIZEY STORE — Supabase project config
# ملاحظة: project_id هو مرجع مشروع Supabase (Project Ref).
project_id = "rglbfizqolrenwfsndyv"

# =========================================================================
# Edge Function: process-receipt
# =========================================================================
# verify_jwt = false ضروري وليس اختيارياً:
#   المتصفح يرسل طلب CORS preflight (OPTIONS) بلا ترويسة Authorization،
#   ومع verify_jwt = true ترفضه بوابة Supabase بـ 401 قبل الوصول إلى
#   معالج OPTIONS داخل الدالة، فيفشل preflight ولا يُرسَل POST إطلاقاً.
#   لذلك نعطّل تحقق البوابة، والدالة نفسها تتحقق من JWT داخلياً عبر
#   admin.auth.getUser(token) وترفض أي طلب بلا جلسة مستخدم صالحة —
#   فالأمان محفوظ كاملاً، مع السماح لـ preflight بالمرور.
[functions.process-receipt]
verify_jwt = false

## RLS and policy statements in tracked SQL
./supabase-critical-fixes-2.sql:27:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-2.sql:86:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-3.sql:33:LANGUAGE sql SECURITY DEFINER STABLE
./supabase-critical-fixes-3.sql:47:LANGUAGE sql SECURITY DEFINER STABLE
./supabase-critical-fixes-3.sql:63:LANGUAGE sql SECURITY DEFINER STABLE
./supabase-critical-fixes-3.sql:74:GRANT EXECUTE ON FUNCTION public.is_admin()       TO anon, authenticated;
./supabase-critical-fixes-3.sql:75:GRANT EXECUTE ON FUNCTION public.is_super_admin() TO anon, authenticated;
./supabase-critical-fixes-3.sql:76:GRANT EXECUTE ON FUNCTION public.is_banned()      TO anon, authenticated;
./supabase-critical-fixes-3.sql:93:    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
./supabase-critical-fixes-3.sql:96:  -- على مالك الجدول (postgres) أيضاً، فتكسر دوال SECURITY DEFINER
./supabase-critical-fixes-3.sql:112:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-3.sql:146:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-3.sql:171:CREATE POLICY "profiles_select_own" ON profiles
./supabase-critical-fixes-3.sql:175:CREATE POLICY "profiles_insert_own" ON profiles
./supabase-critical-fixes-3.sql:180:CREATE POLICY "profiles_update_own" ON profiles
./supabase-critical-fixes-3.sql:185:CREATE POLICY "profiles_admin_all" ON profiles
./supabase-critical-fixes-3.sql:198:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-3.sql:273:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-3.sql:318:CREATE POLICY "orders_select" ON orders
./supabase-critical-fixes-3.sql:323:CREATE POLICY "orders_insert_own" ON orders
./supabase-critical-fixes-3.sql:332:CREATE POLICY "orders_cancel_own" ON orders
./supabase-critical-fixes-3.sql:337:CREATE POLICY "orders_admin_all" ON orders
./supabase-critical-fixes-3.sql:347:-- الرصيد يمر عبر دوال SECURITY DEFINER فقط (شحن/خصم/عمولة).
./supabase-critical-fixes-3.sql:353:CREATE POLICY "wallets_select_own" ON wallets
./supabase-critical-fixes-3.sql:357:CREATE POLICY "wallets_admin_all" ON wallets
./supabase-critical-fixes-3.sql:373:CREATE POLICY "topups_select_own" ON wallet_topups
./supabase-critical-fixes-3.sql:377:CREATE POLICY "topups_insert_own" ON wallet_topups
./supabase-critical-fixes-3.sql:389:CREATE POLICY "topups_admin_all" ON wallet_topups
./supabase-critical-fixes-3.sql:400:CREATE POLICY "products_select_active" ON products
./supabase-critical-fixes-3.sql:403:CREATE POLICY "products_admin_all" ON products
./supabase-critical-fixes-3.sql:409:CREATE POLICY "categories_select" ON categories
./supabase-critical-fixes-3.sql:412:CREATE POLICY "categories_admin" ON categories
./supabase-critical-fixes-3.sql:419:CREATE POLICY "payment_methods_select" ON payment_methods
./supabase-critical-fixes-3.sql:422:CREATE POLICY "payment_methods_admin" ON payment_methods
./supabase-critical-fixes-3.sql:432:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-3.sql:460:CREATE POLICY "notifications_select_own" ON notifications
./supabase-critical-fixes-3.sql:464:CREATE POLICY "notifications_update_own" ON notifications
./supabase-critical-fixes-3.sql:469:CREATE POLICY "notifications_admin_all" ON notifications
./supabase-critical-fixes-3.sql:483:CREATE POLICY "settings_select" ON settings
./supabase-critical-fixes-3.sql:485:CREATE POLICY "settings_admin" ON settings
./supabase-critical-fixes-3.sql:492:CREATE POLICY "store_settings_select" ON store_settings
./supabase-critical-fixes-3.sql:494:CREATE POLICY "store_settings_admin" ON store_settings
./supabase-critical-fixes-3.sql:507:CREATE POLICY "audit_logs_select_admin" ON audit_logs
./supabase-critical-fixes-3.sql:512:CREATE POLICY "audit_logs_insert_customer" ON audit_logs
./supabase-critical-fixes-3.sql:516:CREATE POLICY "audit_logs_admin" ON audit_logs
./supabase-critical-fixes-3.sql:523:CREATE POLICY "admin_audit_select" ON admin_audit_logs
./supabase-critical-fixes-3.sql:526:CREATE POLICY "admin_audit_insert" ON admin_audit_logs
./supabase-critical-fixes-3.sql:540:CREATE POLICY "admin_perms_select" ON admin_permissions
./supabase-critical-fixes-3.sql:545:CREATE POLICY "admin_perms_super_admin" ON admin_permissions
./supabase-critical-fixes-3.sql:559:CREATE POLICY "gift_cards_select_own" ON gift_cards
./supabase-critical-fixes-3.sql:563:CREATE POLICY "gift_cards_admin" ON gift_cards
./supabase-critical-fixes-3.sql:574:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-3.sql:618:CREATE POLICY "referral_milestones_select" ON referral_milestones
./supabase-critical-fixes-3.sql:620:CREATE POLICY "referral_milestones_admin" ON referral_milestones
./supabase-critical-fixes-3.sql:627:CREATE POLICY "referral_payouts_select" ON referral_milestone_payouts
./supabase-critical-fixes-3.sql:630:CREATE POLICY "referral_payouts_admin" ON referral_milestone_payouts
./supabase-critical-fixes-3.sql:646:CREATE POLICY "coupons_select_admin_only" ON coupons
./supabase-critical-fixes-3.sql:648:CREATE POLICY "coupons_admin" ON coupons
./supabase-critical-fixes-3.sql:655:LANGUAGE sql SECURITY DEFINER STABLE
./supabase-critical-fixes-3.sql:670:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-3.sql:717:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-3.sql:855:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-3.sql:897:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-3.sql:947:      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', fn);
./supabase-critical-fixes-3.sql:948:      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon',   fn);
./supabase-critical-fixes-3.sql:949:      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', fn);
./supabase-critical-fixes-3.sql:957:REVOKE ALL ON FUNCTION public.process_referral_commission(uuid, uuid) FROM anon;
./supabase-critical-fixes-3.sql:958:REVOKE ALL ON FUNCTION public.admin_confirm_topup(uuid)               FROM anon;
./supabase-critical-fixes-3.sql:961:REVOKE CREATE ON SCHEMA public FROM anon, authenticated;
./supabase-critical-fixes-3.sql:979:CREATE POLICY "receipts_upload_own" ON storage.objects
./supabase-critical-fixes-3.sql:986:CREATE POLICY "receipts_read_own" ON storage.objects
./supabase-critical-fixes-3.sql:993:CREATE POLICY "receipts_admin_read" ON storage.objects
./supabase-critical-fixes-3.sql:998:CREATE POLICY "receipts_admin_manage" ON storage.objects
./supabase-critical-fixes-3.sql:1051:-- 20.4 دوال SECURITY DEFINER ما زال anon يستطيع تنفيذها
./supabase-critical-fixes-4.sql:80:    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
./supabase-critical-fixes-4.sql:102:      'CREATE POLICY %I ON public.%I FOR ALL TO authenticated '
./supabase-critical-fixes-4.sql:124:    EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated', t);
./supabase-critical-fixes-4.sql:130:GRANT SELECT ON public.products        TO anon;
./supabase-critical-fixes-4.sql:131:GRANT SELECT ON public.categories      TO anon;
./supabase-critical-fixes-4.sql:132:GRANT SELECT ON public.settings        TO anon;
./supabase-critical-fixes-4.sql:133:GRANT SELECT ON public.store_settings  TO anon;
./supabase-critical-fixes-4.sql:141:    EXECUTE format('GRANT SELECT ON public.%I TO authenticated', t);
./supabase-critical-fixes-4.sql:148:GRANT INSERT, UPDATE, DELETE ON public.products                    TO authenticated; -- أدمن (RLS)
./supabase-critical-fixes-4.sql:149:GRANT INSERT, UPDATE, DELETE ON public.categories                  TO authenticated; -- أدمن (RLS)
./supabase-critical-fixes-4.sql:150:GRANT INSERT, UPDATE, DELETE ON public.payment_methods             TO authenticated; -- أدمن (RLS)
./supabase-critical-fixes-4.sql:151:GRANT INSERT, UPDATE, DELETE ON public.coupons                     TO authenticated; -- أدمن (RLS)
./supabase-critical-fixes-4.sql:152:GRANT INSERT, UPDATE, DELETE ON public.gift_cards                  TO authenticated; -- أدمن (RLS)
./supabase-critical-fixes-4.sql:153:GRANT INSERT, UPDATE, DELETE ON public.settings                    TO authenticated; -- أدمن (RLS)
./supabase-critical-fixes-4.sql:154:GRANT INSERT, UPDATE, DELETE ON public.store_settings              TO authenticated; -- أدمن (RLS)
./supabase-critical-fixes-4.sql:155:GRANT INSERT, UPDATE, DELETE ON public.referral_milestones         TO authenticated; -- أدمن (RLS)
./supabase-critical-fixes-4.sql:156:GRANT INSERT, UPDATE, DELETE ON public.referral_milestone_payouts  TO authenticated; -- أدمن (RLS)
./supabase-critical-fixes-4.sql:157:GRANT INSERT, UPDATE, DELETE ON public.notifications               TO authenticated; -- أدمن ينشئ / العميل is_read
./supabase-critical-fixes-4.sql:158:GRANT INSERT, UPDATE, DELETE ON public.orders                      TO authenticated; -- العميل ينشئ/يلغي + أدمن
./supabase-critical-fixes-4.sql:159:GRANT INSERT, UPDATE, DELETE ON public.wallet_topups               TO authenticated; -- العميل يطلب شحن + أدمن
./supabase-critical-fixes-4.sql:160:GRANT INSERT, UPDATE, DELETE ON public.profiles                    TO authenticated; -- العميل ملفه + أدمن
./supabase-critical-fixes-4.sql:161:GRANT INSERT, UPDATE, DELETE ON public.wallets                     TO authenticated; -- أدمن فقط (RLS)
./supabase-critical-fixes-4.sql:162:GRANT INSERT, UPDATE, DELETE ON public.admin_permissions           TO authenticated; -- سوبر أدمن فقط (RLS)
./supabase-critical-fixes-4.sql:166:GRANT INSERT ON public.audit_logs       TO authenticated;
./supabase-critical-fixes-4.sql:167:GRANT INSERT ON public.admin_audit_logs TO authenticated;
./supabase-critical-fixes-4.sql:168:REVOKE UPDATE, DELETE, TRUNCATE ON public.audit_logs       FROM anon, authenticated;
./supabase-critical-fixes-4.sql:169:REVOKE UPDATE, DELETE, TRUNCATE ON public.admin_audit_logs FROM anon, authenticated;
./supabase-critical-fixes-4.sql:179:    EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE public.%I TO authenticated', s);
./supabase-critical-fixes-4.sql:184:REVOKE CREATE ON SCHEMA public FROM anon, authenticated;
./supabase-critical-fixes-4.sql:185:GRANT  USAGE  ON SCHEMA public TO   anon, authenticated;
./supabase-critical-fixes-4.sql:188:ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES    FROM anon, authenticated;
./supabase-critical-fixes-4.sql:189:ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM anon;
./supabase-critical-fixes-4.sql:193:-- PART 4: تثبيت search_path على كل دوال SECURITY DEFINER
./supabase-critical-fixes-4.sql:195:-- 🔴 الثغرة: دالة SECURITY DEFINER بلا "SET search_path" تُنفَّذ بصلاحيات
./supabase-critical-fixes-4.sql:258:    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', r.sig);
./supabase-critical-fixes-4.sql:259:    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon',   r.sig);
./supabase-critical-fixes-4.sql:260:    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
./supabase-critical-fixes-4.sql:263:      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon', r.sig);
./supabase-critical-fixes-4.sql:283:    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon, PUBLIC', r.sig);
./supabase-critical-fixes-4.sql:306:CREATE POLICY "product_images_public_read" ON storage.objects
./supabase-critical-fixes-4.sql:310:CREATE POLICY "product_images_admin_write" ON storage.objects
./supabase-critical-fixes-4.sql:314:CREATE POLICY "product_images_admin_update" ON storage.objects
./supabase-critical-fixes-4.sql:319:CREATE POLICY "product_images_admin_delete" ON storage.objects
./supabase-critical-fixes-4.sql:351:REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON storage.objects FROM anon;
./supabase-critical-fixes-4.sql:398:-- 7.6 دالة SECURITY DEFINER بلا search_path مثبّت
./supabase-critical-fixes-5.sql:102:ALTER TABLE public.payment_receipts ENABLE ROW LEVEL SECURITY;
./supabase-critical-fixes-5.sql:136:CREATE POLICY "receipts_select_own" ON public.payment_receipts
./supabase-critical-fixes-5.sql:141:-- (SECURITY DEFINER) فلا نمنح INSERT للعميل إطلاقاً.
./supabase-critical-fixes-5.sql:142:CREATE POLICY "receipts_admin_all" ON public.payment_receipts
./supabase-critical-fixes-5.sql:176:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-5.sql:290:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-5.sql:408:LANGUAGE plpgsql SECURITY DEFINER STABLE
./supabase-critical-fixes-5.sql:454:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-5.sql:503:CREATE POLICY "coupon_redemptions_select_own" ON public.coupon_redemptions
./supabase-critical-fixes-5.sql:506:CREATE POLICY "coupon_redemptions_admin" ON public.coupon_redemptions
./supabase-critical-fixes-5.sql:525:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-5.sql:665:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-5.sql:839:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-5.sql:897:REVOKE ALL ON FUNCTION public.claim_payment_receipt(text, text, text, text, text, uuid, numeric, numeric, text, text, numeric, text[], jsonb) FROM anon, public;
./supabase-critical-fixes-5.sql:898:REVOKE ALL ON FUNCTION public.create_wallet_order(uuid, jsonb, jsonb, text, text)  FROM anon, public;
./supabase-critical-fixes-5.sql:899:REVOKE ALL ON FUNCTION public.create_wallet_orders_bulk(jsonb, text)               FROM anon, public;
./supabase-critical-fixes-5.sql:900:REVOKE ALL ON FUNCTION public.validate_coupon(text, numeric)                       FROM anon, public;
./supabase-critical-fixes-5.sql:901:REVOKE ALL ON FUNCTION public.use_coupon_atomic(text, numeric)                     FROM anon, public;
./supabase-critical-fixes-5.sql:902:REVOKE ALL ON FUNCTION public.redeem_gift_card(text)                               FROM anon, public;
./supabase-critical-fixes-5.sql:904:GRANT EXECUTE ON FUNCTION public.claim_payment_receipt(text, text, text, text, text, uuid, numeric, numeric, text, text, numeric, text[], jsonb) TO authenticated;
./supabase-critical-fixes-5.sql:905:GRANT EXECUTE ON FUNCTION public.create_wallet_order(uuid, jsonb, jsonb, text, text)  TO authenticated;
./supabase-critical-fixes-5.sql:906:GRANT EXECUTE ON FUNCTION public.create_wallet_orders_bulk(jsonb, text)               TO authenticated;
./supabase-critical-fixes-5.sql:907:GRANT EXECUTE ON FUNCTION public.validate_coupon(text, numeric)                       TO authenticated;
./supabase-critical-fixes-5.sql:908:GRANT EXECUTE ON FUNCTION public.use_coupon_atomic(text, numeric)                      TO authenticated;
./supabase-critical-fixes-5.sql:909:GRANT EXECUTE ON FUNCTION public.redeem_gift_card(text)                               TO authenticated;
./supabase-critical-fixes-5.sql:910:GRANT EXECUTE ON FUNCTION public.normalize_tx_ref(text)                               TO authenticated, anon;
./supabase-critical-fixes-5.sql:912:GRANT SELECT ON public.payment_receipts TO authenticated;
./supabase-critical-fixes-6.sql:44:LANGUAGE plpgsql SECURITY DEFINER STABLE
./supabase-critical-fixes-6.sql:107:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-6.sql:315:REVOKE ALL ON FUNCTION public.create_bank_orders_bulk(jsonb, jsonb, text) FROM anon, public;
./supabase-critical-fixes-6.sql:316:REVOKE ALL ON FUNCTION public.check_tx_ref_available(text)                FROM anon, public;
./supabase-critical-fixes-6.sql:318:GRANT EXECUTE ON FUNCTION public.create_bank_orders_bulk(jsonb, jsonb, text) TO authenticated;
./supabase-critical-fixes-6.sql:319:GRANT EXECUTE ON FUNCTION public.check_tx_ref_available(text)                TO authenticated;
./supabase-critical-fixes-7.sql:46:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-7.sql:165:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-7.sql:375:REVOKE ALL ON FUNCTION public.create_bank_orders_bulk(jsonb, jsonb, text) FROM anon, public;
./supabase-critical-fixes-7.sql:376:GRANT EXECUTE ON FUNCTION public.create_bank_orders_bulk(jsonb, jsonb, text) TO authenticated;
./supabase-critical-fixes-7.sql:387:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-7.sql:446:REVOKE ALL ON FUNCTION public.attach_secondary_receipt(text, uuid, jsonb) FROM anon, public;
./supabase-critical-fixes-7.sql:447:GRANT EXECUTE ON FUNCTION public.attach_secondary_receipt(text, uuid, jsonb) TO authenticated;
./supabase-critical-fixes-7.sql:471:GRANT SELECT, INSERT, UPDATE, DELETE ON public.payment_codes TO authenticated;
./supabase-critical-fixes-7.sql:472:GRANT ALL ON public.payment_codes TO service_role;
./supabase-critical-fixes-7.sql:474:ALTER TABLE public.payment_codes ENABLE ROW LEVEL SECURITY;
./supabase-critical-fixes-7.sql:480:CREATE POLICY "payment_codes_select_own" ON public.payment_codes
./supabase-critical-fixes-7.sql:484:CREATE POLICY "payment_codes_admin_all" ON public.payment_codes
./supabase-critical-fixes-7.sql:494:LANGUAGE plpgsql SECURITY DEFINER STABLE
./supabase-critical-fixes-7.sql:529:REVOKE ALL ON FUNCTION public.validate_payment_code(text) FROM anon, public;
./supabase-critical-fixes-7.sql:530:GRANT EXECUTE ON FUNCTION public.validate_payment_code(text) TO authenticated;
./supabase-critical-fixes-7.sql:542:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-7.sql:723:REVOKE ALL ON FUNCTION public.redeem_payment_code_order(text, jsonb, text) FROM anon, public;
./supabase-critical-fixes-7.sql:724:GRANT EXECUTE ON FUNCTION public.redeem_payment_code_order(text, jsonb, text) TO authenticated;
./supabase-critical-fixes-8.sql:123:ALTER TABLE public.payment_codes ENABLE ROW LEVEL SECURITY;
./supabase-critical-fixes-8.sql:129:CREATE POLICY "payment_codes_admin_all" ON public.payment_codes
./supabase-critical-fixes-8.sql:134:CREATE POLICY "payment_codes_select_own" ON public.payment_codes
./supabase-critical-fixes-8.sql:138:REVOKE ALL ON public.payment_codes FROM anon;
./supabase-critical-fixes-8.sql:139:GRANT SELECT, INSERT, UPDATE, DELETE ON public.payment_codes TO authenticated;
./supabase-critical-fixes-8.sql:150:LANGUAGE plpgsql SECURITY DEFINER STABLE
./supabase-critical-fixes-8.sql:220:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-8.sql:420:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-8.sql:647:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-8.sql:822:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-8.sql:955:LANGUAGE plpgsql SECURITY DEFINER STABLE
./supabase-critical-fixes-8.sql:1005:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-8.sql:1065:LANGUAGE plpgsql SECURITY DEFINER
./supabase-critical-fixes-8.sql:1129:REVOKE ALL ON FUNCTION public.validate_payment_code(text)                       FROM anon, public;
./supabase-critical-fixes-8.sql:1130:REVOKE ALL ON FUNCTION public.redeem_payment_code_order(text, jsonb, text)      FROM anon, public;
./supabase-critical-fixes-8.sql:1131:REVOKE ALL ON FUNCTION public.create_bank_orders_bulk(jsonb, jsonb, text)       FROM anon, public;
./supabase-critical-fixes-8.sql:1132:REVOKE ALL ON FUNCTION public.create_wallet_orders_bulk(jsonb, text)            FROM anon, public;
./supabase-critical-fixes-8.sql:1133:REVOKE ALL ON FUNCTION public.create_wallet_order(uuid, jsonb, jsonb, text, text) FROM anon, public;
./supabase-critical-fixes-8.sql:1134:REVOKE ALL ON FUNCTION public.validate_coupon(text, numeric)                    FROM anon, public;
./supabase-critical-fixes-8.sql:1135:REVOKE ALL ON FUNCTION public.use_coupon_atomic(text, numeric)                  FROM anon, public;
./supabase-critical-fixes-8.sql:1136:REVOKE ALL ON FUNCTION public.attach_secondary_receipt(text, uuid, jsonb)       FROM anon, public;
./supabase-critical-fixes-8.sql:1138:GRANT EXECUTE ON FUNCTION public.validate_payment_code(text)                       TO authenticated;
./supabase-critical-fixes-8.sql:1139:GRANT EXECUTE ON FUNCTION public.redeem_payment_code_order(text, jsonb, text)      TO authenticated;
./supabase-critical-fixes-8.sql:1140:GRANT EXECUTE ON FUNCTION public.create_bank_orders_bulk(jsonb, jsonb, text)       TO authenticated;
./supabase-critical-fixes-8.sql:1141:GRANT EXECUTE ON FUNCTION public.create_wallet_orders_bulk(jsonb, text)            TO authenticated;
./supabase-critical-fixes-8.sql:1142:GRANT EXECUTE ON FUNCTION public.create_wallet_order(uuid, jsonb, jsonb, text, text) TO authenticated;
./supabase-critical-fixes-8.sql:1143:GRANT EXECUTE ON FUNCTION public.validate_coupon(text, numeric)                    TO authenticated;
./supabase-critical-fixes-8.sql:1144:GRANT EXECUTE ON FUNCTION public.use_coupon_atomic(text, numeric)                  TO authenticated;
./supabase-critical-fixes-8.sql:1145:GRANT EXECUTE ON FUNCTION public.attach_secondary_receipt(text, uuid, jsonb)       TO authenticated;
./supabase-fix-payment-code-overload.sql:36:LANGUAGE plpgsql SECURITY DEFINER STABLE
./supabase-fix-payment-code-overload.sql:100:LANGUAGE plpgsql SECURITY DEFINER
./supabase-fix-payment-code-overload.sql:287:REVOKE ALL ON FUNCTION public.validate_payment_code(text)                        FROM anon, public;
./supabase-fix-payment-code-overload.sql:288:REVOKE ALL ON FUNCTION public.redeem_payment_code_order(text, jsonb, text)       FROM anon, public;
./supabase-fix-payment-code-overload.sql:289:GRANT EXECUTE ON FUNCTION public.validate_payment_code(text)                     TO authenticated;
./supabase-fix-payment-code-overload.sql:290:GRANT EXECUTE ON FUNCTION public.redeem_payment_code_order(text, jsonb, text)    TO authenticated;
./supabase-security.sql:27:ALTER TABLE IF EXISTS profiles                   ENABLE ROW LEVEL SECURITY;
./supabase-security.sql:28:ALTER TABLE IF EXISTS orders                     ENABLE ROW LEVEL SECURITY;
./supabase-security.sql:29:ALTER TABLE IF EXISTS products                   ENABLE ROW LEVEL SECURITY;
./supabase-security.sql:30:ALTER TABLE IF EXISTS categories                 ENABLE ROW LEVEL SECURITY;
./supabase-security.sql:31:ALTER TABLE IF EXISTS wallets                    ENABLE ROW LEVEL SECURITY;
./supabase-security.sql:32:ALTER TABLE IF EXISTS wallet_topups              ENABLE ROW LEVEL SECURITY;
./supabase-security.sql:33:ALTER TABLE IF EXISTS payment_methods            ENABLE ROW LEVEL SECURITY;
./supabase-security.sql:34:ALTER TABLE IF EXISTS notifications              ENABLE ROW LEVEL SECURITY;
./supabase-security.sql:35:ALTER TABLE IF EXISTS settings                   ENABLE ROW LEVEL SECURITY;
./supabase-security.sql:36:ALTER TABLE IF EXISTS audit_logs                 ENABLE ROW LEVEL SECURITY;
./supabase-security.sql:37:ALTER TABLE IF EXISTS coupons                    ENABLE ROW LEVEL SECURITY;
./supabase-security.sql:39:ALTER TABLE IF EXISTS gift_cards                 ENABLE ROW LEVEL SECURITY;
./supabase-security.sql:40:ALTER TABLE IF EXISTS referral_milestones        ENABLE ROW LEVEL SECURITY;
./supabase-security.sql:41:ALTER TABLE IF EXISTS referral_milestone_payouts ENABLE ROW LEVEL SECURITY;
./supabase-security.sql:70:ALTER TABLE coupon_redemptions ENABLE ROW LEVEL SECURITY;
./supabase-security.sql:95:-- SECURITY DEFINER لتفادي التكرار اللانهائي في سياسات profiles،
./supabase-security.sql:100:LANGUAGE sql SECURITY DEFINER STABLE
./supabase-security.sql:118:CREATE POLICY "profiles_select_own" ON profiles
./supabase-security.sql:122:CREATE POLICY "profiles_update_own" ON profiles
./supabase-security.sql:132:CREATE POLICY "profiles_insert_own" ON profiles
./supabase-security.sql:138:CREATE POLICY "profiles_admin_all" ON profiles
./supabase-security.sql:154:-- ملاحظة تقنية: create_wallet_order هي SECURITY DEFINER لكن auth.uid()
./supabase-security.sql:160:LANGUAGE plpgsql SECURITY DEFINER
./supabase-security.sql:253:CREATE POLICY "orders_select" ON orders
./supabase-security.sql:256:CREATE POLICY "orders_insert_own" ON orders
./supabase-security.sql:260:CREATE POLICY "orders_cancel_own" ON orders
./supabase-security.sql:264:CREATE POLICY "orders_admin_all" ON orders
./supabase-security.sql:272:-- دوال SECURITY DEFINER في الأجزاء 14–19.
./supabase-security.sql:277:CREATE POLICY "wallets_select_own" ON wallets
./supabase-security.sql:280:CREATE POLICY "wallets_admin_all" ON wallets
./supabase-security.sql:289:CREATE POLICY "products_select_active" ON products
./supabase-security.sql:291:CREATE POLICY "products_admin_all" ON products
./supabase-security.sql:296:CREATE POLICY "categories_select" ON categories FOR SELECT USING (true);
./supabase-security.sql:297:CREATE POLICY "categories_admin"  ON categories FOR ALL    USING (public.is_admin());
./supabase-security.sql:302:CREATE POLICY "payment_methods_select" ON payment_methods
./supabase-security.sql:305:CREATE POLICY "payment_methods_admin" ON payment_methods
./supabase-security.sql:316:CREATE POLICY "topups_select_own" ON wallet_topups
./supabase-security.sql:320:CREATE POLICY "topups_insert_own" ON wallet_topups
./supabase-security.sql:327:CREATE POLICY "topups_admin_all" ON wallet_topups
./supabase-security.sql:341:CREATE POLICY "notifications_select_own" ON notifications
./supabase-security.sql:344:CREATE POLICY "notifications_insert_own" ON notifications
./supabase-security.sql:347:CREATE POLICY "notifications_update_own" ON notifications
./supabase-security.sql:351:CREATE POLICY "notifications_admin_all" ON notifications
./supabase-security.sql:361:CREATE POLICY "settings_select_public" ON settings
./supabase-security.sql:372:CREATE POLICY "settings_admin" ON settings
./supabase-security.sql:380:CREATE POLICY "audit_logs_admin" ON audit_logs
./supabase-security.sql:383:CREATE POLICY "audit_logs_insert_customer" ON audit_logs
./supabase-security.sql:394:CREATE POLICY "coupons_admin" ON coupons
./supabase-security.sql:399:CREATE POLICY "coupon_redemptions_select_own" ON coupon_redemptions
./supabase-security.sql:401:CREATE POLICY "coupon_redemptions_admin" ON coupon_redemptions
./supabase-security.sql:409:CREATE POLICY "gift_cards_admin" ON gift_cards
./supabase-security.sql:420:CREATE POLICY "milestones_select" ON referral_milestones
./supabase-security.sql:422:CREATE POLICY "milestones_admin" ON referral_milestones
./supabase-security.sql:427:CREATE POLICY "milestone_payouts_select_own" ON referral_milestone_payouts
./supabase-security.sql:429:CREATE POLICY "milestone_payouts_admin" ON referral_milestone_payouts

## Financial RPC patterns
./supabase-critical-fixes-2.sql:11:--      يناديها مباشرة من كونسول المتصفح بأي p_user_id و p_order_id.
./supabase-critical-fixes-2.sql:14:--   3) بدون تحقق أن الطلب (order) فعلاً يخص المستخدم p_user_id.
./supabase-critical-fixes-2.sql:20:ALTER TABLE orders ADD COLUMN IF NOT EXISTS referral_commission_paid boolean DEFAULT false;
./supabase-critical-fixes-2.sql:22:CREATE OR REPLACE FUNCTION public.process_referral_commission(
./supabase-critical-fixes-2.sql:24:  p_order_id uuid
./supabase-critical-fixes-2.sql:32:  v_order       RECORD;
./supabase-critical-fixes-2.sql:36:  -- 1) للأدمن فقط — نفس فحص admin_refund_wallet
./supabase-critical-fixes-2.sql:43:  SELECT * INTO v_order FROM orders WHERE id = p_order_id AND user_id = p_user_id FOR UPDATE;
./supabase-critical-fixes-2.sql:48:  IF v_order.referral_commission_paid = true THEN
./supabase-critical-fixes-2.sql:52:  IF v_order.status NOT IN ('in_progress', 'completed') THEN
./supabase-critical-fixes-2.sql:63:  UPDATE orders
./supabase-critical-fixes-2.sql:65:  WHERE id = p_order_id AND referral_commission_paid = false
./supabase-critical-fixes-2.sql:72:  v_commission := ROUND(v_order.price_sdg_snapshot * 0.02, 2); -- 2% عمولة
./supabase-critical-fixes-2.sql:73:  UPDATE wallets SET balance = balance + v_commission, updated_at = now() WHERE user_id = v_referrer_id;
./supabase-critical-fixes-2.sql:84:CREATE OR REPLACE FUNCTION public.admin_confirm_topup(p_topup_id uuid)
./supabase-critical-fixes-2.sql:97:  SELECT * INTO v_topup FROM wallet_topups WHERE id = p_topup_id FOR UPDATE;
./supabase-critical-fixes-2.sql:106:  UPDATE wallet_topups
./supabase-critical-fixes-2.sql:110:  -- إضافة ذرّية للرصيد (balance = balance + amount) بدل قراءة-ثم-كتابة
./supabase-critical-fixes-2.sql:111:  UPDATE wallets
./supabase-critical-fixes-2.sql:112:  SET balance = balance + v_topup.amount, updated_at = now()
./supabase-critical-fixes-2.sql:116:    RAISE EXCEPTION 'wallet_not_found';
./supabase-critical-fixes-3.sql:18:-- coupon_id: يستخدمه trigger التحقق من السعر و create_wallet_order
./supabase-critical-fixes-3.sql:19:ALTER TABLE orders ADD COLUMN IF NOT EXISTS coupon_id uuid REFERENCES coupons(id) ON DELETE SET NULL;
./supabase-critical-fixes-3.sql:21:ALTER TABLE orders ADD COLUMN IF NOT EXISTS field_labels jsonb DEFAULT '{}'::jsonb;
./supabase-critical-fixes-3.sql:23:ALTER TABLE orders ADD COLUMN IF NOT EXISTS referral_commission_paid boolean DEFAULT false;
./supabase-critical-fixes-3.sql:31:CREATE OR REPLACE FUNCTION public.is_admin()
./supabase-critical-fixes-3.sql:45:CREATE OR REPLACE FUNCTION public.is_super_admin()
./supabase-critical-fixes-3.sql:61:CREATE OR REPLACE FUNCTION public.is_banned()
./supabase-critical-fixes-3.sql:97:  -- (create_wallet_order, admin_confirm_topup, redeem_gift_card) و
./supabase-critical-fixes-3.sql:110:CREATE OR REPLACE FUNCTION public.protect_profile_fields()
./supabase-critical-fixes-3.sql:144:CREATE OR REPLACE FUNCTION public.protect_profile_insert()
./supabase-critical-fixes-3.sql:192:-- PART 4: orders — تصحيح trigger السعر + تجميد الأعمدة الحسّاسة
./supabase-critical-fixes-3.sql:196:CREATE OR REPLACE FUNCTION public.verify_order_price_before_insert()
./supabase-critical-fixes-3.sql:263:DROP TRIGGER IF EXISTS trg_verify_order_price ON orders;
./supabase-critical-fixes-3.sql:264:CREATE TRIGGER trg_verify_order_price
./supabase-critical-fixes-3.sql:265:BEFORE INSERT ON orders
./supabase-critical-fixes-3.sql:266:FOR EACH ROW EXECUTE FUNCTION public.verify_order_price_before_insert();
./supabase-critical-fixes-3.sql:268:-- 🟠 المشكلة القديمة: سياسة "orders_cancel_own" كانت تسمح للعميل بتعديل
./supabase-critical-fixes-3.sql:271:CREATE OR REPLACE FUNCTION public.protect_order_fields()
./supabase-critical-fixes-3.sql:292:  NEW.receipt_url              := OLD.receipt_url;
./supabase-critical-fixes-3.sql:293:  NEW.receipt_hash             := OLD.receipt_hash;
./supabase-critical-fixes-3.sql:307:DROP TRIGGER IF EXISTS trg_protect_order_fields ON orders;
./supabase-critical-fixes-3.sql:308:CREATE TRIGGER trg_protect_order_fields
./supabase-critical-fixes-3.sql:309:BEFORE UPDATE ON orders
./supabase-critical-fixes-3.sql:310:FOR EACH ROW EXECUTE FUNCTION public.protect_order_fields();
./supabase-critical-fixes-3.sql:312:DROP POLICY IF EXISTS "orders_select"     ON orders;
./supabase-critical-fixes-3.sql:313:DROP POLICY IF EXISTS "orders_insert_own" ON orders;
./supabase-critical-fixes-3.sql:314:DROP POLICY IF EXISTS "orders_cancel_own" ON orders;
./supabase-critical-fixes-3.sql:315:DROP POLICY IF EXISTS "orders_admin_all"  ON orders;
./supabase-critical-fixes-3.sql:316:DROP POLICY IF EXISTS "orders_delete"     ON orders;
./supabase-critical-fixes-3.sql:318:CREATE POLICY "orders_select" ON orders
./supabase-critical-fixes-3.sql:323:CREATE POLICY "orders_insert_own" ON orders
./supabase-critical-fixes-3.sql:332:CREATE POLICY "orders_cancel_own" ON orders
./supabase-critical-fixes-3.sql:337:CREATE POLICY "orders_admin_all" ON orders
./supabase-critical-fixes-3.sql:344:-- PART 5: wallets — قراءة فقط للمالك، لا كتابة من الكلينت إطلاقاً
./supabase-critical-fixes-3.sql:348:DROP POLICY IF EXISTS "wallets_select_own" ON wallets;
./supabase-critical-fixes-3.sql:349:DROP POLICY IF EXISTS "wallets_admin_all"  ON wallets;
./supabase-critical-fixes-3.sql:350:DROP POLICY IF EXISTS "wallets_update_own" ON wallets;
./supabase-critical-fixes-3.sql:351:DROP POLICY IF EXISTS "wallets_insert_own" ON wallets;
./supabase-critical-fixes-3.sql:353:CREATE POLICY "wallets_select_own" ON wallets
./supabase-critical-fixes-3.sql:357:CREATE POLICY "wallets_admin_all" ON wallets
./supabase-critical-fixes-3.sql:364:-- PART 6: wallet_topups — فرض الحالة والمبلغ من جهة السيرفر
./supabase-critical-fixes-3.sql:368:DROP POLICY IF EXISTS "topups_select_own" ON wallet_topups;
./supabase-critical-fixes-3.sql:369:DROP POLICY IF EXISTS "topups_insert_own" ON wallet_topups;
./supabase-critical-fixes-3.sql:370:DROP POLICY IF EXISTS "topups_admin_all"  ON wallet_topups;
./supabase-critical-fixes-3.sql:371:DROP POLICY IF EXISTS "topups_update_own" ON wallet_topups;
./supabase-critical-fixes-3.sql:373:CREATE POLICY "topups_select_own" ON wallet_topups
./supabase-critical-fixes-3.sql:377:CREATE POLICY "topups_insert_own" ON wallet_topups
./supabase-critical-fixes-3.sql:389:CREATE POLICY "topups_admin_all" ON wallet_topups
./supabase-critical-fixes-3.sql:430:CREATE OR REPLACE FUNCTION public.protect_notification_fields()
./supabase-critical-fixes-3.sql:572:CREATE OR REPLACE FUNCTION public.redeem_gift_card(p_code text)
./supabase-critical-fixes-3.sql:603:  INSERT INTO wallets (user_id, balance)
./supabase-critical-fixes-3.sql:606:  SET balance = wallets.balance + v_card.amount, updated_at = now();
./supabase-critical-fixes-3.sql:653:CREATE OR REPLACE FUNCTION public.validate_coupon(p_code TEXT)
./supabase-critical-fixes-3.sql:668:CREATE OR REPLACE FUNCTION public.use_coupon_atomic(p_code TEXT)
./supabase-critical-fixes-3.sql:704:-- PART 15: create_wallet_order — تصحيح أعمدة الكوبون + حفظ coupon_id
./supabase-critical-fixes-3.sql:706:DROP FUNCTION IF EXISTS public.create_wallet_order(uuid, jsonb, text, text);
./supabase-critical-fixes-3.sql:707:DROP FUNCTION IF EXISTS public.create_wallet_order(uuid, jsonb, jsonb, text, text);
./supabase-critical-fixes-3.sql:709:CREATE OR REPLACE FUNCTION public.create_wallet_order(
./supabase-critical-fixes-3.sql:723:  v_wallet_balance   NUMERIC;
./supabase-critical-fixes-3.sql:731:  v_order_id         uuid;
./supabase-critical-fixes-3.sql:820:  SELECT balance INTO v_wallet_balance
./supabase-critical-fixes-3.sql:821:  FROM wallets WHERE user_id = v_user_id FOR UPDATE;
./supabase-critical-fixes-3.sql:823:  IF v_wallet_balance IS NULL OR v_wallet_balance < v_price_sdg THEN
./supabase-critical-fixes-3.sql:824:    RAISE EXCEPTION 'insufficient_balance';
./supabase-critical-fixes-3.sql:827:  UPDATE wallets SET balance = balance - v_price_sdg, updated_at = now()
./supabase-critical-fixes-3.sql:830:  INSERT INTO orders (
./supabase-critical-fixes-3.sql:838:    'wallet', 'in_progress', v_coupon_id
./supabase-critical-fixes-3.sql:840:  RETURNING orders.id INTO v_order_id;
./supabase-critical-fixes-3.sql:842:  RETURN QUERY SELECT v_order_id;
./supabase-critical-fixes-3.sql:850:CREATE OR REPLACE FUNCTION public.process_referral_commission(
./supabase-critical-fixes-3.sql:852:  p_order_id uuid
./supabase-critical-fixes-3.sql:860:  v_order       RECORD;
./supabase-critical-fixes-3.sql:869:  SELECT * INTO v_order FROM orders
./supabase-critical-fixes-3.sql:870:  WHERE id = p_order_id AND user_id = p_user_id FOR UPDATE;
./supabase-critical-fixes-3.sql:873:  IF COALESCE(v_order.referral_commission_paid, false) = true THEN RETURN; END IF;
./supabase-critical-fixes-3.sql:874:  IF v_order.status NOT IN ('in_progress', 'completed') THEN RETURN; END IF;
./supabase-critical-fixes-3.sql:880:  UPDATE orders SET referral_commission_paid = true
./supabase-critical-fixes-3.sql:881:  WHERE id = p_order_id AND COALESCE(referral_commission_paid, false) = false
./supabase-critical-fixes-3.sql:886:  v_commission := ROUND(COALESCE(v_order.price_sdg_snapshot, 0) * 0.02, 2);
./supabase-critical-fixes-3.sql:889:  INSERT INTO wallets (user_id, balance) VALUES (v_referrer_id, v_commission)
./supabase-critical-fixes-3.sql:891:  SET balance = wallets.balance + v_commission, updated_at = now();
./supabase-critical-fixes-3.sql:895:CREATE OR REPLACE FUNCTION public.admin_confirm_topup(p_topup_id uuid)
./supabase-critical-fixes-3.sql:907:  SELECT * INTO v_topup FROM wallet_topups WHERE id = p_topup_id FOR UPDATE;
./supabase-critical-fixes-3.sql:916:  UPDATE wallet_topups
./supabase-critical-fixes-3.sql:921:  INSERT INTO wallets (user_id, balance) VALUES (v_topup.user_id, v_topup.amount)
./supabase-critical-fixes-3.sql:923:  SET balance = wallets.balance + v_topup.amount, updated_at = now();
./supabase-critical-fixes-3.sql:940:    'public.create_wallet_order(uuid, jsonb, jsonb, text, text)',
./supabase-critical-fixes-3.sql:971:UPDATE storage.buckets SET public = false WHERE id = 'receipts';
./supabase-critical-fixes-3.sql:973:DROP POLICY IF EXISTS "receipts_upload_own"   ON storage.objects;
./supabase-critical-fixes-3.sql:974:DROP POLICY IF EXISTS "receipts_read_own"     ON storage.objects;
./supabase-critical-fixes-3.sql:975:DROP POLICY IF EXISTS "receipts_admin_read"   ON storage.objects;
./supabase-critical-fixes-3.sql:976:DROP POLICY IF EXISTS "receipts_admin_manage" ON storage.objects;
./supabase-critical-fixes-3.sql:978:-- كل مستخدم يرفع في مجلده الخاص فقط: receipts/<uid>/...
./supabase-critical-fixes-3.sql:979:CREATE POLICY "receipts_upload_own" ON storage.objects
./supabase-critical-fixes-3.sql:982:    bucket_id = 'receipts'
./supabase-critical-fixes-3.sql:986:CREATE POLICY "receipts_read_own" ON storage.objects
./supabase-critical-fixes-3.sql:989:    bucket_id = 'receipts'
./supabase-critical-fixes-3.sql:993:CREATE POLICY "receipts_admin_read" ON storage.objects
./supabase-critical-fixes-3.sql:995:  USING (bucket_id = 'receipts' AND public.is_admin());
./supabase-critical-fixes-3.sql:998:CREATE POLICY "receipts_admin_manage" ON storage.objects
./supabase-critical-fixes-3.sql:1000:  USING (bucket_id = 'receipts' AND public.is_admin());
./supabase-critical-fixes-3.sql:1006:CREATE INDEX IF NOT EXISTS idx_orders_status       ON orders(status);
./supabase-critical-fixes-3.sql:1007:CREATE INDEX IF NOT EXISTS idx_orders_user_id      ON orders(user_id);
./supabase-critical-fixes-3.sql:1008:CREATE INDEX IF NOT EXISTS idx_orders_created_at   ON orders(created_at DESC);
./supabase-critical-fixes-3.sql:1009:CREATE INDEX IF NOT EXISTS idx_orders_coupon_id    ON orders(coupon_id) WHERE coupon_id IS NOT NULL;
./supabase-critical-fixes-3.sql:1010:CREATE INDEX IF NOT EXISTS idx_orders_receipt_hash ON orders(receipt_hash) WHERE receipt_hash IS NOT NULL;
./supabase-critical-fixes-3.sql:1011:CREATE INDEX IF NOT EXISTS idx_topups_receipt_hash ON wallet_topups(receipt_hash) WHERE receipt_hash IS NOT NULL;
./supabase-critical-fixes-3.sql:1012:CREATE INDEX IF NOT EXISTS idx_topups_user_status  ON wallet_topups(user_id, status);
./supabase-critical-fixes-3.sql:1046:  AND tablename IN ('orders','wallets','wallet_topups','profiles','coupons',
./supabase-critical-fixes-4.sql:10:--     "Allow select for all users on orders"  USING (true)
./supabase-critical-fixes-4.sql:31:    -- orders
./supabase-critical-fixes-4.sql:32:    'orders_select','orders_insert_own','orders_cancel_own','orders_admin_all',
./supabase-critical-fixes-4.sql:33:    -- wallets
./supabase-critical-fixes-4.sql:34:    'wallets_select_own','wallets_admin_all',
./supabase-critical-fixes-4.sql:35:    -- wallet_topups
./supabase-critical-fixes-4.sql:158:GRANT INSERT, UPDATE, DELETE ON public.orders                      TO authenticated; -- العميل ينشئ/يلغي + أدمن
./supabase-critical-fixes-4.sql:159:GRANT INSERT, UPDATE, DELETE ON public.wallet_topups               TO authenticated; -- العميل يطلب شحن + أدمن
./supabase-critical-fixes-4.sql:161:GRANT INSERT, UPDATE, DELETE ON public.wallets                     TO authenticated; -- أدمن فقط (RLS)
./supabase-critical-fixes-4.sql:227:--    create_wallet_order(uuid, jsonb, text) جنباً إلى جنب مع النسخة
./supabase-critical-fixes-4.sql:236:DROP FUNCTION IF EXISTS public.create_wallet_order(uuid, jsonb, text);
./supabase-critical-fixes-4.sql:237:DROP FUNCTION IF EXISTS public.create_wallet_order(uuid, jsonb, text, text);
./supabase-critical-fixes-4.sql:280:                        'admin_refund_wallet','bootstrap_super_admin',
./supabase-critical-fixes-4.sql:295:-- الفحص أظهر أن bucket "receipts" ما زال public = true، أي أن أي شخص
./supabase-critical-fixes-4.sql:297:UPDATE storage.buckets SET public = false WHERE id = 'receipts';
./supabase-critical-fixes-4.sql:335:    'receipts_upload_own','receipts_read_own','receipts_admin_read','receipts_admin_manage',
./supabase-critical-fixes-4.sql:379:  AND tablename IN ('orders','wallets','wallet_topups','profiles','coupons',
./supabase-critical-fixes-4.sql:413:SELECT id, public AS "⚠️ حالة bucket" FROM storage.buckets WHERE id = 'receipts';
./supabase-critical-fixes-5.sql:17:--    التريجر public.verify_order_price_before_insert يرفض أي إدخال
./supabase-critical-fixes-5.sql:18:--    فيه payment_type = 'wallet' برسالة use_create_wallet_order_rpc
./supabase-critical-fixes-5.sql:19:--    إلا إذا كانت علامة الجلسة raizey.trusted_order = 'on'.
./supabase-critical-fixes-5.sql:20:--    النسخة الأخيرة من create_wallet_order (في fixes-3 / PART 15)
./supabase-critical-fixes-5.sql:22:--        PERFORM set_config('raizey.trusted_order','on',true);
./supabase-critical-fixes-5.sql:27:-- 2) 🔴 الفهرس uq_orders_receipt_hash فريد على مستوى الصف الواحد،
./supabase-critical-fixes-5.sql:28:--    بينما سلة فيها منتجَين تُدخل صفَّي orders بنفس بصمة الإيصال
./supabase-critical-fixes-5.sql:31:--    payment_receipts (صف واحد لكل إيصال) وربط الطلبات به.
./supabase-critical-fixes-5.sql:35:--    القاعدة عبر claim_payment_receipt + قيود UNIQUE حقيقية.
./supabase-critical-fixes-5.sql:53:CREATE OR REPLACE FUNCTION public.normalize_tx_ref(p_ref text)
./supabase-critical-fixes-5.sql:65:-- PART 1: جدول الإيصالات الموحّد payment_receipts
./supabase-critical-fixes-5.sql:70:--   • بصمة صورة الإيصال SHA-256 (receipt_hash)
./supabase-critical-fixes-5.sql:71:CREATE TABLE IF NOT EXISTS public.payment_receipts (
./supabase-critical-fixes-5.sql:74:  purpose           text NOT NULL CHECK (purpose IN ('order', 'topup')),
./supabase-critical-fixes-5.sql:80:  receipt_hash      text NOT NULL,              -- بصمة الصورة (فريدة)
./supabase-critical-fixes-5.sql:81:  receipt_path      text,                       -- مسار الملف في Storage
./supabase-critical-fixes-5.sql:93:CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_receipts_tx_norm
./supabase-critical-fixes-5.sql:94:  ON public.payment_receipts (tx_ref_norm);
./supabase-critical-fixes-5.sql:96:CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_receipts_hash
./supabase-critical-fixes-5.sql:97:  ON public.payment_receipts (receipt_hash);
./supabase-critical-fixes-5.sql:99:CREATE INDEX IF NOT EXISTS idx_payment_receipts_user
./supabase-critical-fixes-5.sql:100:  ON public.payment_receipts (user_id, created_at DESC);
./supabase-critical-fixes-5.sql:102:ALTER TABLE public.payment_receipts ENABLE ROW LEVEL SECURITY;
./supabase-critical-fixes-5.sql:105:ALTER TABLE public.orders
./supabase-critical-fixes-5.sql:106:  ADD COLUMN IF NOT EXISTS receipt_id uuid REFERENCES public.payment_receipts(id);
./supabase-critical-fixes-5.sql:107:ALTER TABLE public.wallet_topups
./supabase-critical-fixes-5.sql:108:  ADD COLUMN IF NOT EXISTS receipt_id uuid REFERENCES public.payment_receipts(id);
./supabase-critical-fixes-5.sql:110:CREATE INDEX IF NOT EXISTS idx_orders_receipt_id  ON public.orders(receipt_id);
./supabase-critical-fixes-5.sql:111:CREATE INDEX IF NOT EXISTS idx_topups_receipt_id  ON public.wallet_topups(receipt_id);
./supabase-critical-fixes-5.sql:114:-- (التكرار الآن محكوم في payment_receipts، وهذا هو المكان الصحيح له)
./supabase-critical-fixes-5.sql:115:DROP INDEX IF EXISTS public.uq_orders_receipt_hash;
./supabase-critical-fixes-5.sql:116:DROP INDEX IF EXISTS public.uq_topups_receipt_hash;
./supabase-critical-fixes-5.sql:117:DROP INDEX IF EXISTS public.uq_orders_transaction_reference;
./supabase-critical-fixes-5.sql:121:CREATE INDEX IF NOT EXISTS idx_orders_receipt_hash
./supabase-critical-fixes-5.sql:122:  ON public.orders(receipt_hash) WHERE receipt_hash IS NOT NULL;
./supabase-critical-fixes-5.sql:123:CREATE INDEX IF NOT EXISTS idx_topups_receipt_hash
./supabase-critical-fixes-5.sql:124:  ON public.wallet_topups(receipt_hash) WHERE receipt_hash IS NOT NULL;
./supabase-critical-fixes-5.sql:125:CREATE INDEX IF NOT EXISTS idx_orders_txref_norm
./supabase-critical-fixes-5.sql:126:  ON public.orders (public.normalize_tx_ref(transaction_reference));
./supabase-critical-fixes-5.sql:128:  ON public.wallet_topups (public.normalize_tx_ref(transaction_reference));
./supabase-critical-fixes-5.sql:131:DROP POLICY IF EXISTS "receipts_select_own"  ON public.payment_receipts;
./supabase-critical-fixes-5.sql:132:DROP POLICY IF EXISTS "receipts_admin_all"   ON public.payment_receipts;
./supabase-critical-fixes-5.sql:133:DROP POLICY IF EXISTS "receipts_no_write"    ON public.payment_receipts;
./supabase-critical-fixes-5.sql:136:CREATE POLICY "receipts_select_own" ON public.payment_receipts
./supabase-critical-fixes-5.sql:140:-- الأدمن فقط يعدّل/يحذف. الإدخال يمر عبر claim_payment_receipt حصراً
./supabase-critical-fixes-5.sql:142:CREATE POLICY "receipts_admin_all" ON public.payment_receipts
./supabase-critical-fixes-5.sql:148:-- PART 2: claim_payment_receipt — الحاجز الذرّي ضد التكرار
./supabase-critical-fixes-5.sql:155:--   duplicate_receipt_image    → نفس صورة الإيصال مستخدمة من قبل
./supabase-critical-fixes-5.sql:156:--   invalid_receipt_input      → بيانات ناقصة
./supabase-critical-fixes-5.sql:157:--   receipt_rejected           → الفحص الذكي رفض الإيصال
./supabase-critical-fixes-5.sql:158:DROP FUNCTION IF EXISTS public.claim_payment_receipt(text, text, uuid, text, text, text, numeric, numeric, jsonb);
./supabase-critical-fixes-5.sql:160:CREATE OR REPLACE FUNCTION public.claim_payment_receipt(
./supabase-critical-fixes-5.sql:163:  p_receipt_hash      text,
./supabase-critical-fixes-5.sql:164:  p_receipt_path      text    DEFAULT NULL,
./supabase-critical-fixes-5.sql:195:  IF p_purpose NOT IN ('order', 'topup') THEN
./supabase-critical-fixes-5.sql:196:    RAISE EXCEPTION 'invalid_receipt_input';
./supabase-critical-fixes-5.sql:200:  v_hash := lower(trim(coalesce(p_receipt_hash, '')));
./supabase-critical-fixes-5.sql:204:    RAISE EXCEPTION 'invalid_receipt_input';
./supabase-critical-fixes-5.sql:208:    RAISE EXCEPTION 'invalid_receipt_input';
./supabase-critical-fixes-5.sql:213:    RAISE EXCEPTION 'receipt_rejected';
./supabase-critical-fixes-5.sql:218:    SELECT 1 FROM orders
./supabase-critical-fixes-5.sql:221:    SELECT 1 FROM wallet_topups
./supabase-critical-fixes-5.sql:227:  IF EXISTS (SELECT 1 FROM orders        WHERE lower(receipt_hash) = v_hash)
./supabase-critical-fixes-5.sql:228:  OR EXISTS (SELECT 1 FROM wallet_topups WHERE lower(receipt_hash) = v_hash) THEN
./supabase-critical-fixes-5.sql:229:    RAISE EXCEPTION 'duplicate_receipt_image';
./supabase-critical-fixes-5.sql:251:    INSERT INTO payment_receipts (
./supabase-critical-fixes-5.sql:254:      receipt_hash, receipt_path,
./supabase-critical-fixes-5.sql:261:      v_hash, p_receipt_path,
./supabase-critical-fixes-5.sql:266:    RETURNING payment_receipts.id INTO v_id;
./supabase-critical-fixes-5.sql:269:      IF EXISTS (SELECT 1 FROM payment_receipts WHERE tx_ref_norm = v_norm) THEN
./supabase-critical-fixes-5.sql:272:        RAISE EXCEPTION 'duplicate_receipt_image';
./supabase-critical-fixes-5.sql:288:CREATE OR REPLACE FUNCTION public.verify_order_price_before_insert()
./supabase-critical-fixes-5.sql:295:  v_receipt      RECORD;
./supabase-critical-fixes-5.sql:304:  IF COALESCE(current_setting('raizey.trusted_order', true), '') = 'on'
./supabase-critical-fixes-5.sql:353:  IF NEW.payment_type = 'wallet' THEN
./supabase-critical-fixes-5.sql:354:    RAISE EXCEPTION 'use_create_wallet_order_rpc';
./supabase-critical-fixes-5.sql:359:    IF NEW.receipt_id IS NULL THEN
./supabase-critical-fixes-5.sql:360:      RAISE EXCEPTION 'receipt_required';
./supabase-critical-fixes-5.sql:363:    SELECT * INTO v_receipt FROM payment_receipts
./supabase-critical-fixes-5.sql:364:    WHERE id = NEW.receipt_id AND user_id = auth.uid() AND purpose = 'order';
./supabase-critical-fixes-5.sql:366:      RAISE EXCEPTION 'receipt_not_owned';
./supabase-critical-fixes-5.sql:370:    NEW.transaction_reference := v_receipt.tx_ref_raw;
./supabase-critical-fixes-5.sql:371:    NEW.receipt_hash          := v_receipt.receipt_hash;
./supabase-critical-fixes-5.sql:372:    NEW.ocr_status            := v_receipt.ocr_status;
./supabase-critical-fixes-5.sql:373:    NEW.amount_verified       := v_receipt.amount_verified;
./supabase-critical-fixes-5.sql:386:DROP TRIGGER IF EXISTS trg_verify_order_price ON public.orders;
./supabase-critical-fixes-5.sql:387:CREATE TRIGGER trg_verify_order_price
./supabase-critical-fixes-5.sql:388:BEFORE INSERT ON public.orders
./supabase-critical-fixes-5.sql:389:FOR EACH ROW EXECUTE FUNCTION public.verify_order_price_before_insert();
./supabase-critical-fixes-5.sql:403:CREATE OR REPLACE FUNCTION public.validate_coupon(
./supabase-critical-fixes-5.sql:405:  p_order_total numeric DEFAULT NULL
./supabase-critical-fixes-5.sql:419:  SELECT c.id, c.discount_percent, COALESCE(c.min_order_sdg, 0) AS min_order_sdg
./supabase-critical-fixes-5.sql:439:  IF p_order_total IS NOT NULL AND v_coupon.min_order_sdg > 0
./supabase-critical-fixes-5.sql:440:     AND p_order_total < v_coupon.min_order_sdg THEN
./supabase-critical-fixes-5.sql:441:    RAISE EXCEPTION 'coupon_min_order';
./supabase-critical-fixes-5.sql:449:CREATE OR REPLACE FUNCTION public.use_coupon_atomic(
./supabase-critical-fixes-5.sql:451:  p_order_total numeric DEFAULT NULL
./supabase-critical-fixes-5.sql:480:  IF p_order_total IS NOT NULL AND COALESCE(v_coupon.min_order_sdg, 0) > 0
./supabase-critical-fixes-5.sql:481:     AND p_order_total < v_coupon.min_order_sdg THEN
./supabase-critical-fixes-5.sql:482:    RAISE EXCEPTION 'coupon_min_order';
./supabase-critical-fixes-5.sql:512:-- PART 5: 🔴 الإصلاح الأساسي — create_wallet_order مع العلامة الموثوقة
./supabase-critical-fixes-5.sql:514:DROP FUNCTION IF EXISTS public.create_wallet_order(uuid, jsonb, text, text);
./supabase-critical-fixes-5.sql:515:DROP FUNCTION IF EXISTS public.create_wallet_order(uuid, jsonb, jsonb, text, text);
./supabase-critical-fixes-5.sql:517:CREATE OR REPLACE FUNCTION public.create_wallet_order(
./supabase-critical-fixes-5.sql:531:  v_wallet_balance   numeric;
./supabase-critical-fixes-5.sql:539:  v_order_id         uuid;
./supabase-critical-fixes-5.sql:612:  SELECT balance INTO v_wallet_balance
./supabase-critical-fixes-5.sql:613:  FROM wallets WHERE user_id = v_user_id FOR UPDATE;
./supabase-critical-fixes-5.sql:615:  IF v_wallet_balance IS NULL THEN
./supabase-critical-fixes-5.sql:616:    RAISE EXCEPTION 'wallet_missing';
./supabase-critical-fixes-5.sql:618:  IF v_wallet_balance < v_price_sdg THEN
./supabase-critical-fixes-5.sql:619:    RAISE EXCEPTION 'insufficient_balance';
