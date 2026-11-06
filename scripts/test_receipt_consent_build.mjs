import fs from 'node:fs';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const env={...process.env};delete env.MEEM_ACCOUNT_CONSENT_PREVIEW;delete env.VERCEL_ENV;
const build=extra=>spawnSync(process.execPath,['scripts/build-public.mjs'],{env:{...env,...extra},encoding:'utf8'});
try {
  assert.equal(build({VERCEL_ENV:'production'}).status,0);
  assert.match(fs.readFileSync('dist/wallet.html','utf8'),/id="geminiConsentWallet"/);
  assert.equal(build({MEEM_ACCOUNT_CONSENT_PREVIEW:'1'}).status,0);
  for(const name of ['wallet','checkout-v2']) {
    const html=fs.readFileSync('dist/'+name+'.html','utf8');
    assert.ok(!html.includes('geminiConsent'),'preview physically removes per-image controls');
    assert.ok(!html.includes('receipt-consent-legacy'),'preview has no legacy listeners');
    assert.match(html,/receipt-consent\.[a-f0-9]+\.js/);
    assert.match(html,/يُفحص الإيصال آلياً/);
  }
  assert.match(fs.readFileSync('dist/register.html','utf8'),/receipt-consent\.[a-f0-9]+\.js/);
  const blocked=build({MEEM_ACCOUNT_CONSENT_PREVIEW:'1',VERCEL_ENV:'production'});
  assert.notEqual(blocked.status,0);assert.match(blocked.stderr,/blocked pending documented provider review/);
  console.log('Consent build: production compatibility, complete preview UI replacement, auth wiring and production activation block passed.');
} finally {assert.equal(build({}).status,0);}
