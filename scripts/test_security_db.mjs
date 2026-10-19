import fs from 'node:fs';
import assert from 'node:assert/strict';
import { getExampleNumber, getCountries } from 'libphonenumber-js/max';
import examples from 'libphonenumber-js/examples.mobile.json';
import { PGlite } from '@electric-sql/pglite';
const db = new PGlite();
try {
  await db.exec(fs.readFileSync(new URL('../db/tests/audit_baseline_schema.sql', import.meta.url), 'utf8'));
  const migration = fs.readFileSync(new URL('../supabase/migrations/20261018082730_comprehensive_security_audit_fixes.sql', import.meta.url), 'utf8');
  await db.exec(migration);
  await db.exec(migration); // idempotent installation must preserve grants and policies
  await db.exec("ALTER TABLE storage.buckets ADD COLUMN file_size_limit bigint, ADD COLUMN allowed_mime_types text[]; INSERT INTO storage.buckets(id,public) VALUES('banners',true) ON CONFLICT DO NOTHING;");
  const onboardingMigration = fs.readFileSync(new URL('../supabase/migrations/20261018200000_auth_onboarding_banner_controls.sql', import.meta.url), 'utf8');
  await db.exec(onboardingMigration);
  await db.exec(onboardingMigration);
  const countryMigration = fs.readFileSync(new URL('../supabase/migrations/20261019001000_phone_number_country_rules.sql', import.meta.url), 'utf8');
  await db.exec(countryMigration);
  await db.exec(countryMigration);
  let countryChecks=0;
  for (const country of getCountries()) {
    const example=getExampleNumber(country,examples);
    if (!example?.isValid()) continue;
    const result=await db.query('select private.valid_contact_number($1,$2) as number',[example.number,country]);
    assert.equal(result.rows[0].number,example.number,`server/client numbering plan agrees: ${country}`);
    countryChecks++;
  }
  console.log(`Country phone validation: ${countryChecks} library examples agree with PostgreSQL.`);
  const onboarding = await db.exec(fs.readFileSync(new URL('../db/tests/auth_banner_security.sql', import.meta.url), 'utf8'));
  const extraChecks = onboarding.flatMap(r => r.rows || []).filter(r => Object.hasOwn(r, 'passed'));
  for (const check of extraChecks) assert.equal(check.passed, true, check.name);
  console.log(`Auth/banner security: ${extraChecks.length} passed; fixtures rolled back.`);
  const results = await db.exec(fs.readFileSync(new URL('../db/tests/security_audit_20261018.sql', import.meta.url), 'utf8'));
  const checks = results.flatMap(r => r.rows || []).filter(r => Object.hasOwn(r, 'passed'));
  assert.ok(checks.length >= 29, 'the SQL suite must execute every expected boundary');
  for (const check of checks) assert.equal(check.passed, true, `${check.name}: ${JSON.stringify(check.evidence)}`);
  assert.equal((await db.query("select count(*)::int as n from auth.users where id::text like 'a6180000-0000-4000-8000-%'")).rows[0].n, 0, 'fixtures rolled back');
  console.log(`Database security: ${checks.length} passed; migrations applied twice; fixtures rolled back.`);
} finally { await db.close(); }
