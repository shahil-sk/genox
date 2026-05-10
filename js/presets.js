// js/presets.js
// ── Preset chips rendering & application ──────

import { PRESETS } from './state.js';
import { escHtml, toast } from './utils.js';

export function renderPresets() {
  const grid = document.getElementById('presetGrid');
  grid.innerHTML = Object.entries(PRESETS).map(([name, p]) => `
    <button class="preset-chip" data-preset="${escHtml(name)}" aria-pressed="false">
      <span class="preset-chip-name">${escHtml(name)}</span>
      <span class="preset-chip-hint">${escHtml(p.hint || '')}</span>
    </button>
  `).join('');

  grid.querySelectorAll('.preset-chip').forEach(btn => {
    btn.addEventListener('click', () => applyPreset(btn.dataset.preset, btn));
  });
}

function applyPreset(name, btn) {
  document.querySelectorAll('.preset-chip').forEach(b => {
    b.classList.remove('active');
    b.setAttribute('aria-pressed', 'false');
  });
  btn.classList.add('active');
  btn.setAttribute('aria-pressed', 'true');

  const p = PRESETS[name];
  if (!p) return;

  const set = (id, val) => { if (val != null) document.getElementById(id).value = val; };
  set('vcodecSelect',     p.vcodec);
  set('crfInput',         p.crf);
  set('vpresetSelect',    p.vpreset);
  set('resolutionSelect', p.resolution ?? '');
  set('acodecSelect',     p.acodec);
  set('abrInput',         p.abr);

  toast(`Preset applied: ${name}`, 'info');
}
