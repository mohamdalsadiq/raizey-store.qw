import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

const migration = process.argv[2] || `supabase/migrations/${(await fs.readdir('supabase/migrations')).find(name => name.endsWith('_telegram_admin_vault_configuration.sql'))}`;
const db = new PGlite();
try {
  await db.exec(`
    CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
    CREATE SCHEMA private; CREATE SCHEMA vault;
    CREATE TABLE vault.decrypted_secrets(name text PRIMARY KEY, decrypted_secret text);
    INSERT INTO vault.decrypted_secrets VALUES
      ('meem_telegram_bot_token','fixture-token'),
      ('meem_telegram_webhook_secret','fixture-webhook-secret'),
      ('meem_telegram_owner_id','123'),
      ('unrelated_secret','must-never-return');
  `);
  await db.exec(await fs.readFile(migration, 'utf8'));
  for (const role of ['anon', 'authenticated']) {
    await db.exec(`SET ROLE ${role}`);
    try {
      await assert.rejects(db.query('SELECT public.telegram_admin_configuration()'), error => error.code === '42501');
      await assert.rejects(db.query('SELECT private.meem_telegram_configuration()'), error => error.code === '42501');
    } finally { await db.exec('RESET ROLE'); }
  }
  // Even the function owner cannot accidentally expose configuration unless
  // called through the dedicated server role.
  await assert.rejects(db.query('SELECT private.meem_telegram_configuration()'), error => error.code === '42501');
  await db.exec('SET ROLE service_role');
  try {
    const result = await db.query('SELECT public.telegram_admin_configuration() AS config');
    assert.deepEqual(result.rows[0].config, { botToken: 'fixture-token', webhookSecret: 'fixture-webhook-secret', ownerId: '123' });
    assert.doesNotMatch(JSON.stringify(result.rows), /must-never-return/);
  } finally { await db.exec('RESET ROLE'); }
  const shape = await db.query(`SELECT n.nspname,p.prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.proname IN ('meem_telegram_configuration','telegram_admin_configuration') ORDER BY n.nspname`);
  assert.deepEqual(shape.rows, [{ nspname: 'private', prosecdef: true }, { nspname: 'public', prosecdef: false }]);
  console.log('Telegram Vault database checks passed: client denial, service-role access, fixed secret scope, private definer.');
} finally { await db.close(); }
