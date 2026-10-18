import fs from 'node:fs';
import assert from 'node:assert/strict';
import { PGlite } from '@electric-sql/pglite';
const db = new PGlite();
try {
  await db.exec(fs.readFileSync(new URL('../db/tests/audit_baseline_schema.sql', import.meta.url), 'utf8'));
  const migration = fs.readFileSync(new URL('../supabase/migrations/20261018082730_comprehensive_security_audit_fixes.sql', import.meta.url), 'utf8');
  await db.exec(migration);
  await db.exec(migration); // idempotent installation must preserve grants and policies
  const results = await db.exec(fs.readFileSync(new URL('../db/tests/security_audit_20261018.sql', import.meta.url), 'utf8'));
  const checks = results.flatMap(r => r.rows || []).filter(r => Object.hasOwn(r, 'passed'));
  assert.ok(checks.length >= 29, 'the SQL suite must execute every expected boundary');
  for (const check of checks) assert.equal(check.passed, true, `${check.name}: ${JSON.stringify(check.evidence)}`);
  assert.equal((await db.query("select count(*)::int as n from auth.users where id::text like 'a6180000-0000-4000-8000-%'")).rows[0].n, 0, 'fixtures rolled back');
  console.log(`Database security: ${checks.length} passed; migrations applied twice; fixtures rolled back.`);
} finally { await db.close(); }
