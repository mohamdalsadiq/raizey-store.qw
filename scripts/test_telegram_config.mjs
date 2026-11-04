import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createConfigLoader } from '../supabase/functions/telegram-admin/config.ts';

const empty = { botToken: '', webhookSecret: '', ownerId: '' };
const good = { botToken: 'test-token', webhookSecret: 'test-secret', ownerId: '123' };
test('complete environment settings never read Vault', async () => {
  const loader = createConfigLoader(good, async () => { throw new Error('unexpected'); });
  assert.deepEqual(await loader(), good);
});
test('a token saved in Edge secrets combines with owner/webhook settings in Vault', async () => {
  const loader = createConfigLoader({ ...empty, botToken: 'environment-token' }, async () => good);
  assert.deepEqual(await loader(), { ...good, botToken: 'environment-token' });
});
test('Vault settings are cached and refresh after thirty seconds for rotation', async () => {
  let now = 0, calls = 0;
  const loader = createConfigLoader(empty, async () => { calls++; return { ...good }; }, () => now);
  assert.deepEqual(await loader(), good); await loader(); assert.equal(calls, 1);
  now = 30_001; await loader(); assert.equal(calls, 2);
});
test('concurrent cold requests share one Vault request', async () => {
  let calls = 0;
  const loader = createConfigLoader(empty, async () => { calls++; return good; });
  await Promise.all([loader(), loader(), loader()]); assert.equal(calls, 1);
});
test('failed Vault access never caches a successful configuration', async () => {
  let fail = true;
  const loader = createConfigLoader(empty, async () => { if (fail) throw new Error('unavailable'); return good; });
  await assert.rejects(loader()); fail = false; assert.deepEqual(await loader(), good);
});
test('incomplete or invalid Vault settings cannot invent credentials', async () => {
  const loader = createConfigLoader(empty, async () => ({ ownerId: 123, botToken: null }));
  assert.deepEqual(await loader(), empty);
  await assert.rejects(createConfigLoader(empty, async () => null)());
});
