const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');

function loadSupabaseHelpers() {
  const code = fs.readFileSync(path.join(projectRoot, 'assets/js/supabase-client.js'), 'utf8');
  const sandbox = {
    console,
    crypto: {
      subtle: {
        digest: async () => new ArrayBuffer(0)
      }
    },
    window: {
      location: {
        hostname: 'localhost',
        origin: 'https://example.com'
      },
      supabase: {
        createClient: () => ({})
      }
    },
    URL,
    Image: function Image() {},
    Tesseract: undefined,
    sessionStorage: {
      getItem: () => null,
      setItem: () => {}
    },
    setTimeout,
    clearTimeout
  };

  vm.createContext(sandbox);
  vm.runInContext(code, sandbox);
  return sandbox;
}

function read(file) {
  return fs.readFileSync(path.join(projectRoot, file), 'utf8');
}

async function main() {
  const helpers = loadSupabaseHelpers();

  assert.strictEqual(typeof helpers.escapeHtml, 'function', 'escapeHtml must exist');
  assert.strictEqual(typeof helpers.escapeAttribute, 'function', 'escapeAttribute must exist');
  assert.strictEqual(typeof helpers.sanitizeUrl, 'function', 'sanitizeUrl must exist');

  assert.strictEqual(
    helpers.escapeHtml('<img src=x onerror=alert(1)>'),
    '&lt;img src=x onerror=alert(1)&gt;'
  );

  assert.strictEqual(
    helpers.escapeAttribute('" onclick="alert(1)"'),
    '&quot; onclick=&quot;alert(1)&quot;'
  );

  assert.strictEqual(
    helpers.sanitizeUrl('javascript:alert(1)'),
    '',
    'javascript URLs must be rejected'
  );

  assert.strictEqual(
    helpers.sanitizeUrl('https://example.com/receipt.png'),
    'https://example.com/receipt.png'
  );

  const productPage = read('product.html');
  assert.ok(!productPage.includes('⚠️'), 'product.html must not contain emoji warnings');

  const rootSupabaseClient = read('supabase-client.js');
  assert.ok(
    rootSupabaseClient.includes('assets/js/supabase-client.js') || rootSupabaseClient.includes('canonical'),
    'root supabase-client.js must act as compatibility layer instead of diverging implementation'
  );

  console.log('security-hardening tests: OK');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
