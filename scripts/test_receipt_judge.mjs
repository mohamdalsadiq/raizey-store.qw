import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../supabase/functions/process-receipt/receipt-judge-core.ts', import.meta.url), 'utf8')
  .replace('export { ReceiptJudgeCore };', 'globalThis.__judge = ReceiptJudgeCore;');
const context = { console };
vm.runInNewContext(source, context, { filename: 'receipt-judge-core.ts' });
const judge = context.__judge;
if (!judge) throw new Error('judge_not_loaded');

function run(name, text, options, expected) {
  const opts = { ...options, ocrSource: 'server', trustedOcr: true };
  const result = judge.judge(judge.buildContext([text], opts), opts, judge.blankResult());
  const actual = {
    decision: result.decision,
    refVerified: result.refVerified,
    amountVerified: result.amountVerified,
    txRef: result.extracted?.txRef,
    amount: result.extracted?.amount,
  };
  for (const [key, value] of Object.entries(expected)) {
    if (actual[key] !== value) {
      throw new Error(`${name}: expected ${key}=${JSON.stringify(value)}, got ${JSON.stringify(actual)}`);
    }
  }
  console.log(`[PASS] ${name}`, JSON.stringify(actual));
}

run('arabic labeled receipt',
  'بنكك تحويل ناجح\nرقم العملية: FT2507191234\nالمبلغ: 52,332 ج.س\nالتاريخ: 2026-08-17 12:30',
  { expectedAmount: 52332, manualRef: 'FT2507191234' },
  { decision: 'accept', refVerified: true, amountVerified: true, txRef: 'ft2507191234', amount: 52332 });

run('structured arbitration line',
  'البنك: بنكك\nالحالة: successful\nرقم العملية: 250719123456\nالمبلغ: 52 332 SDG',
  { expectedAmount: 52332, manualRef: '250719123456' },
  { decision: 'accept', refVerified: true, amountVerified: true });

run('wrong labeled reference rejects',
  'بنكك\nرقم العملية: FT2507199999\nالمبلغ: 52,332 ج.س\nتم التحويل بنجاح',
  { expectedAmount: 52332, manualRef: 'FT2507191234' },
  { decision: 'reject', refVerified: false, amountVerified: true });

run('review when ref absent',
  'بنكك\nالمبلغ: 52,332 ج.س\nتم التحويل بنجاح',
  { expectedAmount: 52332, manualRef: 'FT2507191234' },
  { decision: 'review', refVerified: false, amountVerified: true });
