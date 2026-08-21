#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
checks = []


def check(name, condition, detail=''):
    checks.append((name, bool(condition), detail))


def inline_js(path, output):
    html = path.read_text(encoding='utf-8')
    scripts = re.findall(r'<script(?:\s[^>]*)?>([\s\S]*?)</script>', html, flags=re.I)
    output.write_text('\n\n'.join(scripts), encoding='utf-8')


index = (ROOT / 'index.html').read_text(encoding='utf-8')
category = (ROOT / 'category.html').read_text(encoding='utf-8')
product = (ROOT / 'product.html').read_text(encoding='utf-8')
checkout = (ROOT / 'checkout.html').read_text(encoding='utf-8')
checkout_v2 = (ROOT / 'checkout-v2.html').read_text(encoding='utf-8')
wallet = (ROOT / 'wallet.html').read_text(encoding='utf-8')
admin = (ROOT / 'admin.html').read_text(encoding='utf-8')
subcategories_admin = (ROOT / 'admin-subcategories.html').read_text(encoding='utf-8')
orders = (ROOT / 'admin-orders.html').read_text(encoding='utf-8')
staff = (ROOT / 'admin-staff.html').read_text(encoding='utf-8')
customers = (ROOT / 'admin-customers.html').read_text(encoding='utf-8')
products_admin = (ROOT / 'admin-products.html').read_text(encoding='utf-8')
categories_admin = (ROOT / 'admin-categories.html').read_text(encoding='utf-8')
settings_admin = (ROOT / 'admin-settings.html').read_text(encoding='utf-8')
coupons_admin = (ROOT / 'admin-coupons.html').read_text(encoding='utf-8')
giftcards_admin = (ROOT / 'admin-giftcards.html').read_text(encoding='utf-8')
audit_admin = (ROOT / 'admin-audit-log.html').read_text(encoding='utf-8')
payment_codes_admin = (ROOT / 'admin-payment-codes.html').read_text(encoding='utf-8')
referral_admin = (ROOT / 'admin-referral-milestones.html').read_text(encoding='utf-8')
nav = (ROOT / 'assets/js/admin-nav.js').read_text(encoding='utf-8')
css = (ROOT / 'assets/css/admin.css').read_text(encoding='utf-8')
main_css = (ROOT / 'assets/css/style.css').read_text(encoding='utf-8')
admin_sql = (ROOT / 'supabase-SQL-التوسعة-الإدارة-والعروض.sql').read_text(encoding='utf-8')
catalog_sql = (ROOT / 'supabase-SQL-إعادة-هيكلة-الكتالوج.sql').read_text(encoding='utf-8')
rollback_catalog_sql = (ROOT / 'supabase-SQL-rollback-to-legacy-catalog.sql').read_text(encoding='utf-8')
receipt_pipeline = (ROOT / 'assets/js/receipt-pipeline.js').read_text(encoding='utf-8')
supabase_client = (ROOT / 'assets/js/supabase-client.js').read_text(encoding='utf-8')
receipt_migration = (ROOT / 'supabase-SQL-نقل-فحص-الإيصالات-إلى-الخادم.sql').read_text(encoding='utf-8')
edge_index = (ROOT / 'supabase/functions/process-receipt/index.ts').read_text(encoding='utf-8')
edge_core = (ROOT / 'supabase/functions/process-receipt/receipt-judge-core.ts').read_text(encoding='utf-8')
rollback_dir = ROOT / 'backups/receipt-browser-legacy-20260817'

check('legacy homepage fetches only primary categories', "from('categories')" in index and "from('subcategories')" not in index and "category.html?id=" in index and 'renderCategories(categories || [])' in index)
check('legacy homepage renders game cards', 'game-card' in index and 'game-btn' in index and 'عرض الباقات' in index)
check('legacy category page loads category products', "from('categories')" in category and "from('products')" in category and "eq('category_id', categoryId)" in category and 'variant-grid' in category)
check('legacy category page supports category id mode', "const categoryId = params.get('id')" in category and "from('categories')" in category and "from('products')" in category)
check('legacy category renders product variant buttons', 'variant-grid' in category and 'variant-btn' in category and 'selectedMainProduct' in category and 'selectedSubOption' in category)
check('legacy category keeps dynamic price and CTA flow', 'getCurrentPriceSDG' in category and 'liveTotalDisplay' in category and 'btn-buy-now' in category and 'btn-secondary-cart' in category and "window.location.href = 'checkout.html'" in category)
check('product route does not load browser OCR', 'tesseract.js' not in product and 'receipt-intel.js' not in product and 'checkout-v2.html' in product)
check('legacy admin dashboard keeps original catalog links', 'admin-products.html' in admin and 'admin-categories.html' in admin and 'admin-orders.html' in admin and 'admin-subcategories.html' not in admin)
check('legacy subcategory page is not in active admin nav', 'admin-subcategories.html' not in admin)
check('legacy admin product form scopes products to category', 'categoryInput' in products_admin and 'category_id: categoryId' in products_admin and "from('categories')" in products_admin)
check('legacy admin keeps flat option builder', 'hasOptionsToggle' in products_admin and 'addOptionRow' in products_admin and 'collectOptions' in products_admin and 'options: collectOptions()' in products_admin)
check('orders labels audit and cancel', 'needs_admin_check' in orders and 'data-action="cancel"' in orders)
check('orders uses protected RPC transitions', 'admin_update_order_status' in orders and 'admin_reject_order' in orders)
check('orders initializes filter chips', "querySelectorAll('#filterRow .chip')" in orders)
check('staff page uses permission RPC', 'admin_set_staff_permissions' in staff and 'is_super_admin' in staff)
check('staff load avoids ambiguous embedded relation', "from('admin_permissions').select('profile_id" in staff and 'retryStaffBtn' in staff)
check('customer role toggle removed', 'toggleRole' not in customers and 'admin-staff.html' in customers)
check('admin alerts use protected counts', 'get_admin_notification_counts' in nav and 'admin-orders.html' in nav and 'admin-topups.html' in nav)
check('admin CSS has red badges and responsive states', 'admin-nav-alert' in css and '@media (max-width: 520px)' in css)
check('admin hierarchy hints styled', 'admin-page-hint' in css)
check('admin hidden error state stays hidden', '.admin-error-state[hidden]' in css)
check('product admin guard', 'manage_products' in products_admin and 'is_banned' in products_admin)
check('category admin guard', 'manage_products' in categories_admin and 'is_banned' in categories_admin)
check('settings admin guard', 'manage_settings' in settings_admin and 'is_banned' in settings_admin)
check('coupon admin guard', 'manage_coupons' in coupons_admin and 'is_banned' in coupons_admin)
check('gift card admin guard', 'manage_gift_cards' in giftcards_admin and 'is_banned' in giftcards_admin)
check('audit log admin guard', 'view_audit_logs' in audit_admin and 'is_banned' in audit_admin)
check('payment code admin guard', 'manage_settings' in payment_codes_admin and 'is_banned' in payment_codes_admin)
check('referral milestone admin guard', 'manage_settings' in referral_admin and 'is_banned' in referral_admin)
check('catalog migration creates strict hierarchy', 'CREATE TABLE IF NOT EXISTS public.subcategories' in catalog_sql and 'subcategory_id' in catalog_sql and 'get_catalog_tree' in catalog_sql)
check('catalog migration scopes subcategory RLS', "has_admin_permission('manage_products')" in catalog_sql and 'subcategories_admin_manage' in catalog_sql)
check('legacy rollback SQL is guarded', 'products_subcategory_id_fkey' in rollback_catalog_sql and 'DROP COLUMN IF EXISTS subcategory_id' in rollback_catalog_sql and 'DROP COLUMN IF EXISTS option_tree' in rollback_catalog_sql and 'orders' in rollback_catalog_sql and 'BEGIN;' in rollback_catalog_sql)
check('SQL has popular products function', 'get_popular_products' in admin_sql and 'completed' in admin_sql)
check('SQL has alert counts function', 'get_admin_notification_counts' in admin_sql and 'needs_admin_check' in admin_sql)
check('SQL has protected order status RPC', 'admin_update_order_status' in admin_sql and 'manage_orders' in admin_sql)
check('SQL has protected rejection RPC', 'admin_reject_order' in admin_sql and 'admin_refund_wallet' in admin_sql)
check('SQL has protected staff RPC', 'admin_set_staff_permissions' in admin_sql and 'cannot_remove_last_super_admin' in admin_sql)
check('SQL has protected ban RPC', 'admin_set_customer_banned' in admin_sql and 'manage_admins' in admin_sql)
check('SQL ties admin tables to exact permissions', "has_admin_permission('manage_products')" in admin_sql and "has_admin_permission('manage_settings')" in admin_sql and "has_admin_permission('manage_coupons')" in admin_sql)
check('SQL protects payment codes and referral milestones', 'payment_codes_admin_manage' in admin_sql and 'referral_milestones_admin' in admin_sql)
check('catalog CSS has responsive subcategory cards', '.catalog-subcategories-grid' in main_css and '.catalog-subcategory-card' in main_css and '@media (max-width: 520px)' in main_css)
check('legacy font stack remains available', ('family=Tajawal' in index or 'family=Cairo' in index) and ('Tajawal' in main_css or 'Cairo' in main_css))
check('receipt pipeline is server-only', 'process-receipt' in receipt_pipeline and 'ReceiptIntel' not in receipt_pipeline and 'Tesseract' not in receipt_pipeline)
check('receipt client forwards user JWT', 'Authorization' in receipt_pipeline and 'getSession' in receipt_pipeline and 'Bearer' in receipt_pipeline)
check('receipt pages do not load browser OCR', 'tesseract.js' not in checkout and 'receipt-intel.js' not in checkout and 'tesseract.js' not in wallet and 'receipt-intel.js' not in wallet and 'tesseract.js' not in product)
check('legacy checkout handoff remains available', 'checkout.html' in category and ('checkout.html' in (ROOT / 'cart.html').read_text(encoding='utf-8') or 'checkout-v2.html' in product))
check('legacy receipt endpoint removed from active Vercel path', not (ROOT / 'api/verify-receipt.js').exists() and 'verify-receipt.js' not in (ROOT / 'vercel.json').read_text(encoding='utf-8'))
check('edge function authenticates and uses server secrets', 'auth.getUser' in edge_index and 'SUPABASE_SERVICE_ROLE_KEY' in edge_index and 'GEMINI_API_KEY' in edge_index and 'Bearer' in receipt_pipeline)
check('edge function saves server scan result', 'receipt_scan_results' in edge_index and 'sha256Hex' in edge_index and 'scanId' in edge_index and 'receiptHash' in edge_index)
check('smart receipt allows only JPG PNG WEBP', 'image/jpeg,image/jpg,image/png,image/webp' in checkout and 'image/jpeg,image/jpg,image/png,image/webp' in checkout_v2 and 'image/jpeg,image/jpg,image/png,image/webp' in wallet and 'image/heic' not in edge_index and 'image/heif' not in edge_index)
check('smart receipt enforces 5MB client and edge limits', 'MAX_UPLOAD_BYTES = 5 * 1024 * 1024' in receipt_pipeline and 'MAX_IMAGE_BYTES = 5 * 1024 * 1024' in edge_index and 'parseImagePayload' in edge_index)
check('smart receipt has clear invalid-file messages', 'صيغة الصورة غير مدعومة' in receipt_pipeline and 'حجم الصورة أكبر من 5 ميجابايت' in receipt_pipeline and 'حجم الصورة أكبر من 5 ميجابايت' in edge_index)
check('edge judge core preserves deterministic rules', 'buildContext' in edge_core and 'judge' in edge_core and 'export { ReceiptJudgeCore }' in edge_core)
check('database binds claims to edge scan', 'receipt_scan_results' in receipt_migration and 'enforce_edge_receipt_scan_claim' in receipt_migration and 'edge_scan_id' in receipt_migration)
check('database consumes scan after financial insert', 'mark_edge_receipt_scan_consumed' in receipt_migration and 'trg_orders_edge_scan_consumed' in receipt_migration and 'trg_wallet_topups_edge_scan_consumed' in receipt_migration)
check('receipt rollback backup is complete', all((rollback_dir / name).exists() for name in ('receipt-intel.js', 'receipt-judge-core.js', 'verify-receipt.js', 'SHA256SUMS.txt', 'ROLLBACK.md')))

pages = (
    'index.html', 'category.html', 'product.html', 'admin.html', 'admin-subcategories.html',
    'admin-orders.html', 'admin-customers.html', 'admin-staff.html', 'admin-products.html',
    'admin-categories.html', 'admin-settings.html', 'admin-coupons.html', 'admin-giftcards.html',
    'admin-audit-log.html', 'admin-payment-codes.html', 'admin-referral-milestones.html',
    'checkout.html', 'checkout-v2.html', 'wallet.html'
)
for page in pages:
    out = ROOT / '.upgrade-check.js'
    inline_js(ROOT / page, out)
    result = subprocess.run(['node', '--check', str(out)], text=True, capture_output=True)
    check(f'{page} inline JavaScript syntax', result.returncode == 0, result.stderr.strip())
    out.unlink(missing_ok=True)

failed = 0
for name, ok, detail in checks:
    print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f" — {detail}" if detail and not ok else ''))
    failed += not ok
print(f"\nUpgrade checks: {len(checks) - failed}/{len(checks)} passed")
sys.exit(1 if failed else 0)
