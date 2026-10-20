import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

// Isolated library-level regression for CVE-2026-27212 and its follow-up.
// Altered built-ins model the upstream advisory prerequisite, not a proven
// attacker-controlled route in the storefront. No shared process is polluted.
const source = fs.readFileSync(new URL('../assets/vendor/swiper/swiper-bundle.min.js', import.meta.url), 'utf8');
for (const method of ['indexOf', 'includes']) {
  const context = vm.createContext({});
  vm.runInContext(source, context);
  const polluted = vm.runInContext(`
    Array.prototype.${method} = () => ${method === 'indexOf' ? '-1' : 'false'};
    Swiper.extendDefaults(JSON.parse('{"__proto__":{"vendorSecurityPolluted":true}}'));
    ({}).vendorSecurityPolluted === true;
  `, context);
  assert.equal(polluted, false, `Swiper must resist ${method} filter bypass`);
}
console.log('Vendor security: 2 isolated prototype-pollution regressions passed.');
