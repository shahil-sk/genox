// js/utils.js
// ── Pure helper functions ─────────────────────

export const escHtml = s =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

export const formatBytes = b =>
  b < 1_048_576 ? (b / 1024).toFixed(1) + 'KB' : (b / 1_048_576).toFixed(1) + 'MB';

export const uid = () => Math.random().toString(36).slice(2, 9);

export function toast(msg, type = 'info') {
  const container = document.getElementById('toasts');
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.innerHTML = `<div class="toast-dot"></div><span class="toast-msg">${escHtml(msg)}</span>`;
  container.appendChild(el);
  setTimeout(() => {
    el.classList.add('out');
    setTimeout(() => el.remove(), 300);
  }, 3000);
}

export function setStatus(text) {
  document.getElementById('statusText').textContent = text;
}
