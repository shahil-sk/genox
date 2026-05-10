// js/main.js
// ── Application entry point ───────────────────

import { initTheme }       from './theme.js';
import { initDropzone, setCommandRenderer } from './files.js';
import { renderPresets }   from './presets.js';
import { renderCommands }  from './commands.js';
import { initOutputPath }  from './outputPath.js';
import { state }           from './state.js';
import { toast, setStatus } from './utils.js';

// Wire the circular dependency: files.js needs to call renderCommands
setCommandRenderer(renderCommands);

// ── Tabs ──────────────────────────────────────
function initTabs() {
  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.tab-btn').forEach(b => {
        b.classList.remove('active');
        b.setAttribute('aria-selected', 'false');
      });
      document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
      btn.classList.add('active');
      btn.setAttribute('aria-selected', 'true');
      document.getElementById('tab-' + btn.dataset.tab).classList.add('active');
    });
  });
}

// ── Live re-generation when settings change ───
function liveUpdate() {
  if (state.files.length > 0 && document.querySelector('.cmd-card')) {
    renderCommands();
  }
}

function initSettingsListeners() {
  const ids = [
    'vcodecSelect', 'crfInput', 'vpresetSelect', 'resolutionSelect', 'bitrateInput',
    'acodecSelect', 'abrInput', 'sampleRateSelect', 'outputFormatSelect',
    'extraArgsInput', 'trimStartInput', 'trimDurInput', 'outputPathInput',
  ];
  ids.forEach(id => {
    const el = document.getElementById(id);
    el.addEventListener('input',  liveUpdate);
    el.addEventListener('change', liveUpdate);
  });
}

// ── Generate button ───────────────────────────
function initGenerateButton() {
  document.getElementById('generateBtn').addEventListener('click', () => {
    if (state.files.length === 0) { toast('Add at least one media file first', 'error'); return; }
    const crf = document.getElementById('crfInput').value.trim();
    if (crf && (isNaN(Number(crf)) || Number(crf) < 0 || Number(crf) > 51)) {
      toast('CRF must be 0–51', 'error'); return;
    }
    renderCommands();
    document.getElementById('cmdSection').scrollIntoView({ behavior: 'smooth', block: 'start' });
  });
}

// ── Bootstrap ─────────────────────────────────
initTheme();
initDropzone();
renderPresets();
initTabs();
initSettingsListeners();
initGenerateButton();
initOutputPath(liveUpdate);
setStatus('Ready');
