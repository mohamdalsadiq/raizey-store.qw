#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
checks = []

def check(name, condition, detail=''):
    checks.append((name, bool(condition), detail))

def extract_inline_js(html_path, out_path):
    html = html_path.read_text(encoding='utf-8')
    scripts = re.findall(r'<script(?:\s[^>]*)?>([\s\S]*?)</script>', html, flags=re.I)
    out_path.write_text('\n\n'.join(scripts), encoding='utf-8')

index = (ROOT / 'index.html').read_text(encoding='utf-8')
category = (ROOT / 'category.html').read_text(encoding='utf-8')
admin = (ROOT / 'admin.html').read_text(encoding='utf-8')
admin_products = (ROOT / 'admin-products.html').read_text(encoding='utf-8')
admin_categories = (ROOT / 'admin-categories.html').read_text(encoding='utf-8')
sql = (ROOT / 'supabase-SQL-المهمة-5.sql').read_text(encoding='utf-8')

check('homepage queries products by category', 'category_id' in index and "from('products')" in index and 'renderCategories(categories || [], products || []' in index)
check('homepage renders product sections', 'catalog-section' in index and 'catalog-product-card' in index and 'sectionProducts' in index)
check('homepage uses safe DOM text rendering', 'textContent' in index and 'escapeHtml' not in index[index.find('function renderCategories'):])
check('homepage supports custom delivery badge', 'delivery_badge_text' in index and 'catalog-delivery-badge' in index)
check('admin dashboard links catalog controls', 'admin-categories.html' in admin and 'catalog-admin-panel' in admin)
check('admin products has badge field', 'deliveryBadgeInput' in admin_products and 'delivery_badge_text:' in admin_products)
check('admin products keeps category binding', 'category_id: categoryId' in admin_products)
check('category page updates badge on variant change', 'deliveryBadge' in category and 'updateDeliveryBadge(selectedMainProduct)' in category)
check('category page hides empty badge', 'deliveryBadge.hidden = !text' in category)
check('admin categories escapes dynamic values', 'escapeHtml(c.name)' in admin_categories and 'sanitizeUrl(c.image_url)' in admin_categories)
check('SQL creates/extends categories', 'CREATE TABLE IF NOT EXISTS public.categories' in sql and 'ADD COLUMN IF NOT EXISTS display_order' in sql)
check('SQL adds category_id and badge', 'ADD COLUMN IF NOT EXISTS category_id uuid' in sql and 'ADD COLUMN IF NOT EXISTS delivery_badge_text text' in sql)
check('SQL has foreign key and index', 'products_category_id_fkey' in sql and 'idx_products_category_active_order' in sql)
check('SQL has RLS and admin policy', 'ENABLE ROW LEVEL SECURITY' in sql and 'public.is_admin()' in sql)

for name in ('index', 'category', 'admin', 'admin-products', 'admin-categories'):
    source = ROOT / f'{name}.html'
    out = ROOT / f'.task5-{name}.js'
    extract_inline_js(source, out)
    result = subprocess.run(['node', '--check', str(out)], text=True, capture_output=True)
    check(f'{name} inline JavaScript syntax', result.returncode == 0, result.stderr.strip())
    out.unlink(missing_ok=True)

failed = 0
for name, ok, detail in checks:
    print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f" — {detail}" if detail and not ok else ''))
    failed += not ok
print(f"\nTask 5 checks: {len(checks) - failed}/{len(checks)} passed")
sys.exit(1 if failed else 0)
