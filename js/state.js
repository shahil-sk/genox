// js/state.js
// ── Shared application state ──────────────────

export const state = { files: [] };

export const PRESETS = {
  'YouTube 1080p': { vcodec: 'libx264', crf: '18', vpreset: 'slow',      resolution: '1920:1080', acodec: 'aac', abr: '128k', hint: 'H.264 · 1080p' },
  'YouTube 720p':  { vcodec: 'libx264', crf: '20', vpreset: 'medium',    resolution: '1280:720',  acodec: 'aac', abr: '128k', hint: 'H.264 · 720p' },
  'H.265 HEVC':    { vcodec: 'libx265', crf: '20', vpreset: 'slow',                               acodec: 'aac', abr: '128k', hint: 'HEVC · slow' },
  'Fast Convert':  { vcodec: 'libx264', crf: '23', vpreset: 'ultrafast',                          acodec: 'copy',             hint: 'CPU fast' },
  'Audio Only':    { vcodec: 'copy',                                                               acodec: 'libmp3lame', abr: '192k', hint: 'MP3 · 192k' },
  'High Quality':  { vcodec: 'libx264', crf: '16', vpreset: 'veryslow',                          acodec: 'aac', abr: '192k', hint: 'CRF 16' },
  'Small Size':    { vcodec: 'libx264', crf: '28', vpreset: 'fast',       resolution: '854:480',  acodec: 'aac', abr: '96k',  hint: '480p · fast' },
  '4K Master':     { vcodec: 'libx264', crf: '18', vpreset: 'slow',       resolution: '3840:2160',acodec: 'aac', abr: '192k', hint: '4K UHD' },
  'iPhone':        { vcodec: 'libx264', crf: '22',                        resolution: '1280:720', acodec: 'aac', abr: '128k', hint: '720p · AAC' },
  'Passthrough':   { vcodec: 'copy',                                                               acodec: 'copy',             hint: 'No re-encode' },
};

export const MEDIA_EXTS = /\.(mp4|mkv|avi|mov|m4a|mp3|wav|webm|flv|m4v|wmv|ts|ogg|opus|aac|ac3|mxf|vob|3gp|rm|rmvb)$/i;
