// js/outputPath.js
// ── Output-path browse widget ─────────────────

export function initOutputPath(onChangeCb) {
  const browseBtn = document.getElementById('outputBrowseBtn');
  const picker    = document.getElementById('outputDirPicker');
  const pathInput = document.getElementById('outputPathInput');
  const clearBtn  = document.getElementById('outputPathClear');
  const hint      = document.getElementById('outputPathHint');

  function updateClear() {
    clearBtn.style.display = pathInput.value.trim() ? '' : 'none';
  }

  function setHintPartial(name) {
    hint.textContent = `⚠ Browser only shows the folder name "${name}" — prepend the full path if needed (e.g. /home/user/${name} or C:\\Users\\you\\${name}).`;
    hint.className = 'outpath-hint partial';
  }
  function setHintSet() {
    hint.textContent = '✓ Output path set. Edit above if the full path differs.';
    hint.className = 'outpath-hint set';
  }
  function setHintDefault() {
    hint.textContent = 'Browse to select a folder, or type the full path. Left blank = output next to input file.';
    hint.className = 'outpath-hint';
  }

  browseBtn.addEventListener('click', () => picker.click());

  picker.addEventListener('change', e => {
    const files = e.target.files;
    if (!files || files.length === 0) return;
    const first      = files[0];
    const folderName = first.webkitRelativePath
      ? first.webkitRelativePath.split('/')[0]
      : first.name;
    pathInput.value = folderName;
    updateClear();
    setHintPartial(folderName);
    onChangeCb();
    e.target.value = '';
  });

  clearBtn.addEventListener('click', () => {
    pathInput.value = '';
    updateClear();
    setHintDefault();
    onChangeCb();
  });

  pathInput.addEventListener('input', () => {
    updateClear();
    pathInput.value.trim() ? setHintSet() : setHintDefault();
  });
}
