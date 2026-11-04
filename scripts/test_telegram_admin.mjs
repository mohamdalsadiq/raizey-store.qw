import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTelegramAdminHandler } from '../supabase/functions/telegram-admin/handler.ts';

const config = { botToken: '123456:TEST_ONLY_TOKEN_WITH_30_CHARACTERS', webhookSecret: 'test_secret_'.repeat(4), ownerId: '123456789' };
const owner = { id: Number(config.ownerId), is_bot: false };
const message = { from: owner, chat: { id: owner.id, type: 'private' }, text: '/test' };
function fixture(overrides = {}) {
  const state = { probes: 0, sent: [] };
  const handler = createTelegramAdminHandler({ ...config, ...overrides }, {
    probeDatabase: async () => { state.probes++; },
    fetch: async (url, options) => {
      state.sent.push({ method: url.split('/').at(-1), body: JSON.parse(options.body) });
      return Response.json({ ok: true });
    },
  });
  return { state, handler };
}
function request(update = { update_id: 1, message }, headers = {}) {
  return new Request('https://example.invalid/telegram-admin', { method: 'POST',
    headers: { 'content-type': 'application/json', 'X-Telegram-Bot-Api-Secret-Token': config.webhookSecret, ...headers },
    body: JSON.stringify(update),
  });
}

test('missing configuration fails closed with no database or Telegram access', async () => {
  for (const overrides of [{ botToken: '' }, { ownerId: '' }, { ownerId: '@m3em_3' }, { webhookSecret: '' }, { ownerId: '9007199254740992' }]) {
    const { handler, state } = fixture(overrides);
    assert.equal((await handler(request())).status, 503);
    assert.equal(state.probes, 0); assert.equal(state.sent.length, 0);
  }
});
test('wrong/missing webhook secret is rejected before parsing or accessing the database', async () => {
  for (const secret of ['', 'incorrect', 'x'.repeat(300)]) {
    const { handler, state } = fixture();
    assert.equal((await handler(request(undefined, { 'X-Telegram-Bot-Api-Secret-Token': secret }))).status, 401);
    assert.equal(state.probes, 0); assert.equal(state.sent.length, 0);
  }
});
test('another user, group chat, anonymous sender and spoofed callback cannot probe', async () => {
  for (const update of [
    { message: { ...message, from: { id: 999, username: 'm3em_3' } } },
    { message: { ...message, chat: { id: -123, type: 'supergroup' } } },
    { message: { ...message, sender_chat: { id: -123 } } },
    { message: { ...message, from: { id: { toString: 'invalid' } } } },
    { callback_query: { id: 'c', from: { id: 999 }, message, data: 'connection:test' } },
    { callback_query: { id: 'c', from: owner, message: { ...message, chat: { id: -123, type: 'group' } }, data: 'connection:test' } },
  ]) {
    const { handler, state } = fixture();
    assert.equal((await handler(request({ update_id: 1, ...update }))).status, 200);
    assert.equal(state.probes, 0); assert.equal(state.sent.length, 0);
  }
});
test('owner test performs read-only probe and sends success without order/customer details', async () => {
  const { handler, state } = fixture();
  assert.equal((await handler(request())).status, 200);
  assert.equal(state.probes, 1); assert.equal(state.sent.length, 1);
  assert.equal(state.sent[0].body.chat_id, owner.id);
  assert.match(state.sent[0].body.text, /نجح اختبار الربط/);
  assert.equal(state.sent[0].body.protect_content, true);
});
test('start only shows a test button; unknown commands never query the database', async () => {
  for (const text of ['/start', '/complete abc', '/test@another_bot']) {
    const { handler, state } = fixture();
    assert.equal((await handler(request({ update_id: 1, message: { ...message, text } }))).status, 200);
    assert.equal(state.probes, 0); assert.equal(state.sent.length, text === '/start' ? 1 : 0);
  }
});
test('owner callback acknowledges and probes; callback data is not an order action', async () => {
  const { handler, state } = fixture();
  const update = { update_id: 2, callback_query: { id: 'callback-2', from: owner, message, data: 'connection:test' } };
  assert.equal((await handler(request(update))).status, 200);
  assert.equal(state.probes, 1);
  assert.deepEqual(state.sent.map(x => x.method), ['answerCallbackQuery', 'sendMessage']);
});
test('payload bounds, invalid JSON/update, methods and media type are enforced', async () => {
  const { handler, state } = fixture();
  assert.equal((await handler(new Request('https://example.invalid'))).status, 405);
  assert.equal((await handler(request(undefined, { 'content-type': 'text/plain' }))).status, 415);
  assert.equal((await handler(request({ update_id: '1', message }))).status, 400);
  assert.equal((await handler(request({ update_id: 1, padding: 'x'.repeat(17000) }))).status, 413);
  assert.equal(state.probes, 0);
});
test('database failure is reported to owner without secrets or false success', async () => {
  const sent = [];
  const handler = createTelegramAdminHandler(config, {
    probeDatabase: async () => { throw new Error('sensitive database details'); },
    fetch: async (_url, options) => { sent.push(JSON.parse(options.body)); return Response.json({ ok: true }); },
  });
  assert.equal((await handler(request())).status, 200);
  assert.match(sent[0].text, /لم ينجح/); assert.doesNotMatch(sent[0].text, /sensitive|نجح اختبار الربط/);
});
test('Telegram errors do not echo a token or upstream error text', async () => {
  const handler = createTelegramAdminHandler(config, { probeDatabase: async () => {}, fetch: async () => { throw new Error(config.botToken); } });
  const result = await handler(request());
  assert.equal(result.status, 502); assert.deepEqual(await result.json(), { error: 'delivery_failed' });
});

test('deployed entrypoint only uses HEAD on orders; database keys never reach Telegram', async () => {
  const originalFetch = globalThis.fetch;
  const originalDeno = globalThis.Deno;
  try {
    for (const modern of [false, true]) {
      const env = {
        TELEGRAM_BOT_TOKEN: config.botToken, TELEGRAM_WEBHOOK_SECRET: config.webhookSecret,
        TELEGRAM_OWNER_ID: config.ownerId, SUPABASE_URL: 'https://project.supabase.co',
        SUPABASE_SERVICE_ROLE_KEY: 'test-legacy-server-key',
        SUPABASE_SECRET_KEYS: modern ? JSON.stringify({ telegram: 'sb_secret_test' }) : '',
      };
      let deployedHandler, probes = 0;
      globalThis.Deno = { env: { get: name => env[name] }, serve: handler => { deployedHandler = handler; } };
      globalThis.fetch = async (url, options) => {
        if (new URL(url).hostname === 'project.supabase.co') {
          probes++;
          assert.equal(options.method, 'HEAD');
          assert.equal(new URL(url).pathname, '/rest/v1/orders');
          assert.equal(new URL(url).searchParams.get('select'), 'id');
          assert.equal(options.headers.apikey, modern ? 'sb_secret_test' : 'test-legacy-server-key');
          assert.equal(options.headers.Authorization, modern ? undefined : 'Bearer test-legacy-server-key');
          assert.equal(options.body, undefined);
          return new Response(null, { status: 200 });
        }
        assert.equal(new URL(url).hostname, 'api.telegram.org');
        assert.doesNotMatch(JSON.stringify(options), /sb_secret_test|test-legacy-server-key/);
        return Response.json({ ok: true });
      };
      await import(`../supabase/functions/telegram-admin/index.ts?key-test=${modern}`);
      assert.equal((await deployedHandler(request())).status, 200);
      assert.equal(probes, 1);
    }
  } finally { globalThis.fetch = originalFetch; globalThis.Deno = originalDeno; }
});
