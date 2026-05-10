// js/commands.js
// ── FFmpeg command generation & output rendering

import { state } from './state.js';
import { escHtml, formatBytes, toast, setStatus } from './utils.js';

// ── Settings reader ───────────────────────────

function readSettings() {
  const val = id => document.getElementById(id).value.trim();
  return {
    vcodec:     document.getElementById('vcodecSelect').value || 'libx264',
    crf:        val('crfInput'),
    vpreset:    document.getElementById('vpresetSelect').value,
    resolution: document.getElementById('resolutionSelect').value,
    bitrate:    val('bitrateInput'),
    acodec:     document.getElementById('acodecSelect').value || 'aac',
    abr:        val('abrInput'),
    sampleRate: document.getElementById('sampleRateSelect').value,
    outFormat:  document.getElementById('outputFormatSelect').value || 'mp4',
    extraArgs:  val('extraArgsInput'),
    trimStart:  val('trimStartInput'),
    trimDur:    val('trimDurInput'),
    outPath:    val('outputPathInput'),
  };
}

// ── Path helpers ──────────────────────────────

function isWinPath(p) {
  return /^[A-Za-z]:[/\\]/.test(p) || p.includes('\\');
}

function buildOutFile(inputPath, outPath, outFormat) {
  const isWin = isWinPath(inputPath) || (outPath && isWinPath(outPath));
  const sep   = isWin ? '\\' : '/';

  const lastSlash = Math.max(inputPath.lastIndexOf('/'), inputPath.lastIndexOf('\\'));
  const fileName  = lastSlash >= 0 ? inputPath.slice(lastSlash + 1) : inputPath;
  const baseName  = fileName.replace(/\.[^.]+$/, '');

  if (outPath) {
    const dir = outPath.replace(/[/\\]$/, '');
    return `"${dir}${sep}${baseName}_converted.${outFormat}"`;
  }

  if (lastSlash >= 0) {
    const dir = inputPath.slice(0, lastSlash);
    return `"${dir}${sep}${baseName}_converted.${outFormat}"`;
  }

  return `"${baseName}_converted.${outFormat}"`;
}

// ── Command builder ───────────────────────────

export function buildCommand(file) {
  const { vcodec, crf, vpreset, resolution, bitrate,
          acodec, abr, sampleRate, outFormat,
          extraArgs, trimStart, trimDur, outPath } = readSettings();

  const inputPath = file.path;
  const parts = ['ffmpeg', '-y'];

  if (trimStart) parts.push('-ss', trimStart);
  if (trimDur)   parts.push('-t',  trimDur);

  parts.push('-i', `"${inputPath}"`);

  if (vcodec === 'copy') {
    parts.push('-c:v', 'copy');
  } else {
    parts.push('-c:v', vcodec);
    if (crf && !isNaN(Number(crf)))         parts.push('-crf', crf);
    if (vpreset && vcodec !== 'libvpx-vp9') parts.push('-preset', vpreset);
    if (bitrate)                             parts.push('-b:v', bitrate);
  }

  if (resolution) parts.push('-vf', `scale=${resolution}:flags=lanczos`);

  if (acodec === 'copy') {
    parts.push('-c:a', 'copy');
  } else {
    parts.push('-c:a', acodec);
    if (abr)        parts.push('-b:a', abr);
    if (sampleRate) parts.push('-ar',  sampleRate);
  }

  if (extraArgs) parts.push(extraArgs);

  parts.push(buildOutFile(inputPath, outPath, outFormat));
  return parts.join(' ');
}

// ── Batch script builders ─────────────────────

function buildBashScript(cmds) {
  const lines = [
    '#!/usr/bin/env bash',
    '# Genox Web — batch FFmpeg script',
    `# Generated: ${new Date().toLocaleString()}`,
    '# Run: chmod +x batch_convert.sh && ./batch_convert.sh',
    '',
    'set -euo pipefail',
    '',
  ];
  cmds.forEach((cmd, i) => {
    lines.push(`echo "[${i + 1}/${cmds.length}] Processing..."`);
    lines.push(cmd);
    lines.push('');
  });
  lines.push('echo "All done!"');
  return lines.join('\n');
}

function buildBatScript(cmds) {
  const lines = [
    '@echo off',
    'REM Genox Web — batch FFmpeg script',
    `REM Generated: ${new Date().toLocaleString()}`,
    'REM Double-click or run in Command Prompt',
    '',
  ];
  cmds.forEach((cmd, i) => {
    lines.push(`echo [${i + 1}/${cmds.length}] Processing...`);
    lines.push(cmd);
    lines.push(`if errorlevel 1 ( echo ERROR on file ${i + 1} & pause & exit /b 1 )`);
    lines.push('');
  });
  lines.push('echo All done!');
  lines.push('pause');
  return lines.join('\r\n');
}

// ── Syntax highlighters ───────────────────────

function highlightCmd(raw) {
  const tokens = [];
  const re = /"[^"]*"|[^\s]+/g;
  let m;
  while ((m = re.exec(raw)) !== null) tokens.push(m[0]);

  return tokens.map((tok, i) => {
    if (i === 0)                                        return `<span class="tok-cmd">${escHtml(tok)}</span>`;
    if (tok.startsWith('-'))                             return `<span class="tok-flag">${escHtml(tok)}</span>`;
    if (tok.startsWith('"') && i === tokens.length - 1) return `<span class="tok-file">${escHtml(tok)}</span>`;
    if (tok.startsWith('"') && i === 2)                 return `<span class="tok-file">${escHtml(tok)}</span>`;
    return `<span class="tok-val">${escHtml(tok)}</span>`;
  }).join(' ');
}

function highlightBatch(raw) {
  return escHtml(raw)
    .replace(/((?:^|\n)(?:#|REM)[^\n]*)/g, '<span class="tok-comment">$1</span>')
    .replace(/\bffmpeg\b/g, '<span class="tok-cmd">ffmpeg</span>')
    .replace(/(^|\s)(-[a-zA-Z:_]+)/g, '$1<span class="tok-flag">$2</span>')
    .replace(/&quot;([^&]*)&quot;/g, '<span class="tok-file">&quot;$1&quot;</span>');
}

// ── Helpers ───────────────────────────────────

function copyText(text, btn) {
  navigator.clipboard.writeText(text).then(() => {
    const orig = btn.innerHTML;
    btn.classList.add('copied');
    btn.innerHTML = `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg> Copied!`;
    setTimeout(() => { btn.classList.remove('copied'); btn.innerHTML = orig; }, 1800);
  }).catch(() => toast('Copy failed — select and copy manually', 'error'));
}

function downloadText(content, filename, mimeType) {
  const url = URL.createObjectURL(new Blob([content], { type: mimeType }));
  const a   = Object.assign(document.createElement('a'), { href: url, download: filename });
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

// ── Batch card ────────────────────────────────

function renderBatchCard(cmds, section) {
  const bash = buildBashScript(cmds);
  const bat  = buildBatScript(cmds);

  const card = document.createElement('div');
  card.className = 'cmd-card batch-card';
  card.innerHTML = `
    <div class="cmd-header batch-header">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"
           style="color:var(--color-primary);flex-shrink:0" aria-hidden="true">
        <path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/>
        <polyline points="13 2 13 9 20 9"/>
        <line x1="8" y1="13" x2="16" y2="13"/>
        <line x1="8" y1="17" x2="16" y2="17"/>
      </svg>
      <span class="cmd-filename">Batch Script — ${cmds.length} files</span>
      <span class="batch-badge">BATCH</span>
    </div>
    <div class="cmd-body">
      <div class="batch-tab-bar">
        <button class="batch-tab active" data-target="bash-view">bash / zsh</button>
        <button class="batch-tab" data-target="bat-view">Windows .bat</button>
      </div>
      <div class="cmd-code batch-code" id="bash-view">${highlightBatch(bash)}</div>
      <div class="cmd-code batch-code" id="bat-view" style="display:none">${highlightBatch(bat)}</div>
      <div class="cmd-actions">
        <button class="btn-copy" id="batch-copy-bash">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
          Copy .sh
        </button>
        <button class="btn-copy" id="batch-copy-bat">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
          Copy .bat
        </button>
        <button class="btn-copy btn-download" id="batch-dl-bash">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
          Download .sh
        </button>
        <button class="btn-copy btn-download" id="batch-dl-bat">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
          Download .bat
        </button>
      </div>
    </div>
  `;

  card.querySelectorAll('.batch-tab').forEach(tab => {
    tab.addEventListener('click', () => {
      card.querySelectorAll('.batch-tab').forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      card.querySelector('#bash-view').style.display = tab.dataset.target === 'bash-view' ? '' : 'none';
      card.querySelector('#bat-view').style.display  = tab.dataset.target === 'bat-view'  ? '' : 'none';
    });
  });

  card.querySelector('#batch-copy-bash').addEventListener('click', e => copyText(bash, e.currentTarget));
  card.querySelector('#batch-copy-bat').addEventListener('click',  e => copyText(bat,  e.currentTarget));
  card.querySelector('#batch-dl-bash').addEventListener('click',   () => downloadText(bash, 'batch_convert.sh',  'text/x-shellscript'));
  card.querySelector('#batch-dl-bat').addEventListener('click',    () => downloadText(bat,  'batch_convert.bat', 'text/plain'));

  section.appendChild(card);
}

// ── Main render ───────────────────────────────

export function renderCommands() {
  const section = document.getElementById('cmdSection');
  const empty   = document.getElementById('cmdEmpty');

  if (state.files.length === 0) {
    section.innerHTML = '';
    section.appendChild(empty);
    empty.style.display = '';
    setStatus('Ready');
    return;
  }

  const allCmds = state.files.map(f => buildCommand(f));
  section.innerHTML = '';

  if (state.files.length > 1) {
    renderBatchCard(allCmds, section);

    const divLabel = document.createElement('p');
    divLabel.className = 'section-label';
    divLabel.style.cssText = 'margin-top:var(--space-3)';
    divLabel.textContent = 'Individual Commands';
    section.appendChild(divLabel);
  }

  state.files.forEach((f, idx) => {
    const cmd  = allCmds[idx];
    const card = document.createElement('div');
    card.className = 'cmd-card';
    card.innerHTML = `
      <div class="cmd-header">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"
             style="color:var(--color-primary);flex-shrink:0" aria-hidden="true">
          <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
          <polyline points="14 2 14 8 20 8"/>
        </svg>
        <span class="cmd-filename" title="${escHtml(f.path)}">${escHtml(f.name)}</span>
        <span class="cmd-filesize">${formatBytes(f.size)}</span>
      </div>
      <div class="cmd-body">
        <div class="cmd-code">${highlightCmd(cmd)}</div>
        <div class="cmd-actions">
          <button class="btn-copy">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
            Copy Command
          </button>
        </div>
      </div>
    `;
    card.querySelector('.btn-copy').addEventListener('click', e => copyText(cmd, e.currentTarget));
    section.appendChild(card);
  });

  const n = state.files.length;
  const label = `${n} command${n > 1 ? 's' : ''} generated`;
  setStatus(label);
  toast(label, 'success');
}
