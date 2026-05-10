// js/files.js
// ── File list state, rendering, and dropzone ──

import { state, MEDIA_EXTS } from './state.js';
import { escHtml, formatBytes, uid, toast } from './utils.js';

// Populated by commands.js after its module loads
let _renderCommands = () => {};
export function setCommandRenderer(fn) { _renderCommands = fn; }

// ── State mutations ───────────────────────────

export function addFiles(fileList) {
  let added = 0;
  Array.from(fileList).forEach(f => {
    if (!MEDIA_EXTS.test(f.name)) return;
    if (state.files.find(x => x.path === (f.webkitRelativePath || f.name) && x.size === f.size)) return;
    // webkitRelativePath gives "folder/file.mp4" for folder picks; use it as a hint.
    // For individual file picks the browser does NOT expose the real absolute path (security),
    // so we store whatever we have and surface a note to the user.
    const path = f.webkitRelativePath || f.name;
    state.files.push({ id: uid(), name: f.name, path, size: f.size });
    added++;
  });
  if (added > 0) {
    renderFileList();
    toast(`Added ${added} file${added > 1 ? 's' : ''}`, 'info');
  } else {
    toast('No new media files found', 'error');
  }
}

export function removeFile(id) {
  state.files = state.files.filter(f => f.id !== id);
  renderFileList();
  _renderCommands();
}

export function clearFiles() {
  state.files = [];
  renderFileList();
  _renderCommands();
}

// ── Rendering ────────────────────────────────

export function renderFileList() {
  const list    = document.getElementById('fileList');
  const section = document.getElementById('fileListSection');
  const count   = document.getElementById('fileCountLabel');
  count.textContent = `(${state.files.length})`;
  if (state.files.length === 0) { section.style.display = 'none'; return; }
  section.style.display = '';
  list.innerHTML = state.files.map(f => `
    <div class="file-item" id="fi-${f.id}">
      <div class="file-icon">
        <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true">
          <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
          <polyline points="14 2 14 8 20 8"/>
        </svg>
      </div>
      <div class="file-info">
        <div class="file-name" title="${escHtml(f.path)}">${escHtml(f.name)}</div>
        <div class="file-meta file-path" title="${escHtml(f.path)}">${escHtml(f.path)}</div>
        <div class="file-meta">${formatBytes(f.size)}</div>
      </div>
      <button class="file-remove" data-id="${f.id}" aria-label="Remove ${escHtml(f.name)}">
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
        </svg>
      </button>
    </div>
  `).join('');

  // Delegate remove-button clicks
  list.querySelectorAll('.file-remove').forEach(btn => {
    btn.addEventListener('click', () => removeFile(btn.dataset.id));
  });
}

// ── Dropzone & file input wiring ─────────────

export function initDropzone() {
  const dz          = document.getElementById('dropzone');
  const fileInput   = document.getElementById('fileInput');
  const folderInput = document.getElementById('folderInput');

  dz.addEventListener('click',    () => fileInput.click());
  dz.addEventListener('keydown',  e  => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); fileInput.click(); } });
  dz.addEventListener('dragover', e  => { e.preventDefault(); dz.classList.add('dragover'); });
  dz.addEventListener('dragleave', e => { if (!dz.contains(e.relatedTarget)) dz.classList.remove('dragover'); });
  dz.addEventListener('drop',     e  => { e.preventDefault(); dz.classList.remove('dragover'); if (e.dataTransfer.files.length) addFiles(e.dataTransfer.files); });

  fileInput.addEventListener('change',   e => { if (e.target.files.length) addFiles(e.target.files); e.target.value = ''; });
  folderInput.addEventListener('change', e => { if (e.target.files.length) addFiles(e.target.files); e.target.value = ''; });

  document.getElementById('addFilesBtn').addEventListener('click',   () => fileInput.click());
  document.getElementById('addFolderBtn').addEventListener('click',  () => folderInput.click());
  document.getElementById('clearFilesBtn').addEventListener('click', clearFiles);
}
