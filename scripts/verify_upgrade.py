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
sql = (ROOT / 'supabase-SQL-التوسعة-الإدارة-والعروض.sql').read_text(encoding='utf-8')

check('homepage has ordered catalog sections', 'الأكثر شراءً' in index and 'getCategoryPriority' in index and 'renderCategories(categories || [], products || [], safePopularProducts' in index)
check('homepage has automatic flash sale banner', 'flashSaleBanner' in index and 'flash_sale_ends_at' in index and 'compare_at_price_usd' in index)
check('homepage keeps category navigation', 'category.html?id=' in index)
check('popular cards open package detail', 'product.html?id=' in index and 'product.product_id || product.id' in index)
check('category has compact option controls', 'min-height: 48px' in category and 'price-value' in category)
check('category has live current and old price', 'oldPriceDisplay' in category and 'updateLiveCalculations' in category)
check('category renders package cards', 'package-card-grid' in category and 'product.html?id=' in category and 'خيارات' in category)
check('orders labels audit and cancel', 'needs_admin_check' in orders and 'data-action="cancel"' in orders)
check('orders uses protected RPC transitions', 'admin_update_order_status' in orders and 'admin_reject_order' in orders)
check('orders initializes filter chips', 'querySelectorAll(\'#filterRow .chip\')' in orders)
check('staff page uses permission RPC', 'admin_set_staff_permissions' in staff and 'is_super_admin' in staff)
check('staff load avoids ambiguous embedded relation', "from('admin_permissions').select('profile_id" in staff and 'retryStaffBtn' in staff)
check('customer role toggle removed', 'toggleRole' not in customers and 'admin-staff.html' in customers)
check('admin alerts use protected counts', 'get_admin_notification_counts' in nav and 'admin-orders.html' in nav and 'admin-topups.html' in nav)
check('admin CSS has red badges and responsive states', 'admin-nav-alert' in css and '@media (max-width: 520px)' in css)
check('admin hierarchy hints styled', 'admin-page-hint' in css)
check('product admin guard', "manage_products" in products_admin and "is_banned" in products_admin)
check('category admin guard', "manage_products" in categories_admin and "is_banned" in categories_admin)
check('settings admin guard', "manage_settings" in settings_admin and "is_banned" in settings_admin)
check('coupon admin guard', "manage_coupons" in coupons_admin and "is_banned" in coupons_admin)
check('gift card admin guard', "manage_gift_cards" in giftcards_admin and "is_banned" in giftcards_admin)
check('audit log admin guard', "view_audit_logs" in audit_admin and "is_banned" in audit_admin)
check('payment code admin guard', "manage_settings" in payment_codes_admin and "is_banned" in payment_codes_admin)
check('referral milestone admin guard', "manage_settings" in referral_admin and "is_banned" in referral_admin)
check('SQL has popular products function', 'get_popular_products' in sql and 'completed' in sql)
check('SQL has alert counts function', 'get_admin_notification_counts' in sql and 'needs_admin_check' in sql)
check('SQL has protected order status RPC', 'admin_update_order_status' in sql and 'manage_orders' in sql)
check('SQL has protected rejection RPC', 'admin_reject_order' in sql and 'admin_refund_wallet' in sql)
check('SQL has protected staff RPC', 'admin_set_staff_permissions' in sql and 'cannot_remove_last_super_admin' in sql)
check('SQL has protected ban RPC', 'admin_set_customer_banned' in sql and 'manage_admins' in sql)
check('SQL ties admin tables to exact permissions', "has_admin_permission('manage_products')" in sql and "has_admin_permission('manage_settings')" in sql and "has_admin_permission('manage_coupons')" in sql)
check('SQL protects payment codes and referral milestones', 'payment_codes_admin_manage' in sql and 'referral_milestones_admin' in sql)
check('Cairo font applied globally', 'family=Cairo' in index and "--font-display: 'Cairo'" in (ROOT / 'assets/css/style.css').read_text(encoding='utf-8'))

for page in ('index.html', 'category.html', 'admin-orders.html', 'admin-customers.html', 'admin-staff.html', 'admin-products.html', 'admin-categories.html', 'admin-settings.html', 'admin-coupons.html', 'admin-giftcards.html', 'admin-audit-log.html', 'admin-payment-codes.html', 'admin-referral-milestones.html'):
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
