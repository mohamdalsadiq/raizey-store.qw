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
    # Only inline scripts are captured by the expression; external tags have no body.
    out_path.write_text('\n\n'.join(scripts), encoding='utf-8')
    return len(scripts)

referrals = (ROOT / 'referrals.html').read_text(encoding='utf-8')
register = (ROOT / 'register.html').read_text(encoding='utf-8')
countries = (ROOT / 'assets/js/country-codes.js').read_text(encoding='utf-8')
sql = (ROOT / 'supabase-SQL-المهمة-4.sql').read_text(encoding='utf-8')

check('referrals has short-code column', 'referral_short_code' in referrals)
check('referrals has copy button', 'copyShortRefBtn' in referrals)
check('referrals escapes user strings', 'function escapeHtml' in referrals and 'escapeHtml(r.full_name' in referrals and 'escapeHtml(n.message' in referrals)
check('register has optional referral field', 'id="referralCode"' in register)
check('register calls validation RPC', 'validate_referral_short_code' in register)
check('register sends metadata', 'referral_code_used: referralCode || null' in register)
check('country picker is text-only', 'flagcdn.com' not in countries and '<img' not in countries and 'country-name' in countries)
check('SQL adds short-code column', 'ADD COLUMN IF NOT EXISTS referral_short_code' in sql)
check('SQL has validation RPC grant', re.search(r'GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.validate_referral_short_code\(text\)\s+TO\s+anon,\s*authenticated', sql, re.I) is not None)
check('SQL prevents self referral', 'self_referral' in sql and 'v_referrer <> NEW.id' in sql)
check('SQL preserves legacy metadata', "referral_code_used" in sql and 'referral_code' in sql)

for name in ('referrals', 'register'):
    source = ROOT / f'{name}.html'
    out = ROOT / f'.task4-{name}.js'
    count = extract_inline_js(source, out)
    result = subprocess.run(['node', '--check', str(out)], text=True, capture_output=True)
    check(f'{name} inline JavaScript syntax', result.returncode == 0, result.stderr.strip() or f'{count} script block(s)')
    out.unlink(missing_ok=True)

result = subprocess.run(['node', '--check', str(ROOT / 'assets/js/country-codes.js')], text=True, capture_output=True)
check('country-codes JavaScript syntax', result.returncode == 0, result.stderr.strip())

failed = 0
for name, ok, detail in checks:
    print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f" — {detail}" if detail and not ok else ''))
    failed += not ok
print(f"\nTask 4 checks: {len(checks) - failed}/{len(checks)} passed")
sys.exit(1 if failed else 0)
