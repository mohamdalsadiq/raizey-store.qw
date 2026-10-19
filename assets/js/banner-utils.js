(function () {
  'use strict';
  const ratios = { '3:2': '3 / 2', '16:9': '16 / 9', '4:3': '4 / 3', '1:1': '1 / 1', '4:5': '4 / 5', '3:4': '3 / 4' };
  function utcToKhartoum(value) {
    return value ? new Date(new Date(value).getTime() + 7200000).toISOString().slice(0, 16) : '';
  }
  function khartoumToUtc(value) {
    if (!value) return null;
    if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value)) throw new Error('INVALID_SCHEDULE');
    const date = new Date(value + ':00+02:00');
    if (!Number.isFinite(date.getTime()) || utcToKhartoum(date) !== value) throw new Error('INVALID_SCHEDULE');
    return date.toISOString();
  }
  function mobileBox(ratio) {
    const [w, h] = (ratios[ratio] ? ratio : '16:9').split(':').map(Number);
    return { w: 1080, h: Math.round(1080 * h / w) };
  }
  window.MeemBannerUtils = { ratios, utcToKhartoum, khartoumToUtc, mobileBox };
})();
