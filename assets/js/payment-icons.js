(function () {
  'use strict';
  document.addEventListener('keydown', function (event) {
    const target = event.target.closest?.('.file-upload[role=button]');
    if (target && ['Enter',' '].includes(event.key)) { event.preventDefault(); target.click(); }
  });
  document.addEventListener('error', function (event) {
    const img = event.target;
    if (!(img instanceof HTMLImageElement) || !img.hasAttribute('data-payment-icon')) return;
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('class', 'mm-i'); svg.setAttribute('aria-hidden', 'true');
    const use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
    use.setAttribute('href', 'assets/icons/lucide-sprite.svg#i-landmark');
    svg.appendChild(use); img.replaceWith(svg);
  }, true);
})();
