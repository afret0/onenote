const DEFAULT_PORT = 41190;
const REQUEST_TIMEOUT_MS = 15000;
const MAX_ATTACHMENT_BYTES = 20 * 1024 * 1024;

const ui = {
  mainView: document.getElementById('mainView'),
  settingsView: document.getElementById('settingsView'),
  connStatus: document.getElementById('connStatus'),
  notebookSelect: document.getElementById('notebookSelect'),
  titleInput: document.getElementById('titleInput'),
  clipArticle: document.getElementById('clipArticle'),
  clipSelection: document.getElementById('clipSelection'),
  clipFullpage: document.getElementById('clipFullpage'),
  clipShot: document.getElementById('clipShot'),
  clipBookmark: document.getElementById('clipBookmark'),
  shotFile: document.getElementById('shotFile'),
  result: document.getElementById('result'),
  openSettings: document.getElementById('openSettings'),
  closeSettings: document.getElementById('closeSettings'),
  portInput: document.getElementById('portInput'),
  portError: document.getElementById('portError'),
  tokenInput: document.getElementById('tokenInput'),
  toggleToken: document.getElementById('toggleToken'),
  saveSettings: document.getElementById('saveSettings'),
  settingsResult: document.getElementById('settingsResult'),
};

let config = { port: DEFAULT_PORT, token: '', lastNotebookId: '' };
let connected = false;
let busy = false;

function baseUrl() {
  return `http://127.0.0.1:${config.port}`;
}

async function loadConfig() {
  const stored = await chrome.storage.local.get([
    'clipPort',
    'clipToken',
    'lastNotebookId',
  ]);
  const port = Number(stored.clipPort);
  config = {
    port:
      Number.isInteger(port) && port >= 1024 && port <= 65535
        ? port
        : DEFAULT_PORT,
    token: typeof stored.clipToken === 'string' ? stored.clipToken : '',
    lastNotebookId:
      typeof stored.lastNotebookId === 'string' ? stored.lastNotebookId : '',
  };
}

async function api(path, options = {}) {
  const headers = Object.assign(
    { 'X-Clip-Token': config.token },
    options.headers || {}
  );
  const response = await fetch(baseUrl() + path, {
    method: options.method || 'GET',
    headers,
    body: options.body ? JSON.stringify(options.body) : undefined,
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });
  const text = await response.text();
  let payload = null;
  try {
    payload = text ? JSON.parse(text) : null;
  } catch (err) {
    payload = null;
  }
  if (!response.ok) {
    const message =
      payload && payload.error
        ? payload.error
        : `应用返回 HTTP ${response.status}`;
    throw new Error(message);
  }
  return { payload, text };
}

function setStatus(text, kind) {
  ui.connStatus.textContent = text;
  ui.connStatus.className = `status ${kind || ''}`.trim();
}

function setResult(target, text, kind) {
  target.textContent = text;
  target.className = `result ${kind || ''}`.trim();
}

function setActionsEnabled(enabled) {
  const usable = enabled && !busy;
  ui.clipArticle.disabled = !usable;
  ui.clipSelection.disabled = !usable;
  ui.clipFullpage.disabled = !usable;
  ui.clipShot.disabled = !usable;
  ui.clipBookmark.disabled = !usable;
  ui.notebookSelect.disabled = !usable;
  ui.titleInput.disabled = !usable;
}

async function prefillTitle() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  ui.titleInput.value = tab && tab.title ? tab.title : '';
}

function titleFor(tab) {
  const typed = ui.titleInput.value.trim();
  return typed || (tab && tab.title ? tab.title : '') || '无标题';
}

function sanitizeName(name) {
  return name.replace(/[\\/:*?"<>|\r\n]+/g, '_').slice(0, 80) || '附件';
}

function blobToBase64(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const url = String(reader.result);
      resolve(url.slice(url.indexOf(',') + 1));
    };
    reader.onerror = () => reject(new Error('读取附件数据失败'));
    reader.readAsDataURL(blob);
  });
}

async function readClipboardImage() {
  try {
    const items = await navigator.clipboard.read();
    for (const item of items) {
      const type = item.types.find((t) => t.startsWith('image/'));
      if (type) {
        const blob = await item.getType(type);
        const ext = (type.split('/')[1] || 'png').replace('jpeg', 'jpg');
        return { blob, mime: type, name: `截图.${ext}` };
      }
    }
  } catch (err) {
    return null;
  }
  return null;
}

function pickImageFile() {
  return new Promise((resolve) => {
    const input = ui.shotFile;
    const done = (value) => {
      input.removeEventListener('change', onChange);
      input.removeEventListener('cancel', onCancel);
      input.value = '';
      resolve(value);
    };
    const onChange = () => {
      const file = input.files && input.files[0];
      done(file ? { blob: file, mime: file.type || 'image/png', name: file.name } : null);
    };
    const onCancel = () => done(null);
    input.addEventListener('change', onChange);
    input.addEventListener('cancel', onCancel);
    input.click();
  });
}

async function sendClip(body) {
  const { payload } = await api('/clips', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
  });
  config.lastNotebookId = body.notebookId;
  await chrome.storage.local.set({ lastNotebookId: body.notebookId });
  const name = ui.notebookSelect.selectedOptions[0]?.textContent || '笔记本';
  setResult(ui.result, `已存入「${name}」：${payload.title || '无标题'}`, 'ok');
}

function requireNotebook() {
  const notebookId = ui.notebookSelect.value;
  if (!notebookId) {
    throw new Error('请先在应用里创建笔记本');
  }
  return notebookId;
}

async function clipShot() {
  if (busy || !connected) {
    return;
  }
  busy = true;
  setActionsEnabled(false);
  setResult(ui.result, '正在剪藏截图…');
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    let image = await readClipboardImage();
    if (!image) {
      image = await pickImageFile();
    }
    if (!image) {
      throw new Error('没有可剪藏的截图：请先截图到剪贴板（⌘⌃⇧4）或选择图片文件');
    }
    if (image.blob.size > MAX_ATTACHMENT_BYTES) {
      throw new Error('截图超过 20MB 上限');
    }
    const data = await blobToBase64(image.blob);
    const sourceUrl = tab && tab.url ? tab.url : undefined;
    await sendClip({
      notebookId: requireNotebook(),
      title: titleFor(tab),
      markdown: '',
      sourceUrl,
      attachment: {
        name: sanitizeName(image.name),
        mime: image.mime,
        data,
      },
    });
  } catch (err) {
    setResult(ui.result, friendlyError(err), 'bad');
  } finally {
    busy = false;
    setActionsEnabled(connected);
  }
}

async function clipFullpage() {
  if (busy || !connected) {
    return;
  }
  busy = true;
  setActionsEnabled(false);
  setResult(ui.result, '正在保存整页…');
  try {
    const tab = await activeTab();
    const blob = await chrome.pageCapture.saveAsMHTML({ tabId: tab.id });
    if (!blob || !blob.size) {
      throw new Error('整页保存失败，请刷新页面后重试');
    }
    if (blob.size > MAX_ATTACHMENT_BYTES) {
      throw new Error('整页超过 20MB 上限，可改用「剪藏正文」');
    }
    const data = await blobToBase64(blob);
    await sendClip({
      notebookId: requireNotebook(),
      title: titleFor(tab),
      markdown: '',
      sourceUrl: tab.url,
      attachment: {
        name: sanitizeName(`${tab.title || '整页'}.mhtml`),
        mime: 'multipart/related',
        data,
      },
    });
  } catch (err) {
    setResult(ui.result, friendlyError(err), 'bad');
  } finally {
    busy = false;
    setActionsEnabled(connected);
  }
}

function friendlyError(err) {
  if (err && err.name === 'TimeoutError') {
    return '连接应用超时：请确认应用正在运行且已启用剪藏服务';
  }
  if (err instanceof TypeError) {
    return '无法连接应用：请确认应用正在运行、已启用剪藏服务且端口一致';
  }
  return err && err.message ? err.message : String(err);
}

async function refreshConnection() {
  connected = false;
  setActionsEnabled(false);
  if (!config.token) {
    setStatus('未配置配对令牌：请先在设置里粘贴应用设置页的令牌', 'bad');
    ui.notebookSelect.replaceChildren();
    return;
  }
  setStatus('正在连接应用…');
  try {
    const { text } = await api('/ping');
    if (text.trim() !== 'onenote') {
      throw new Error('该端口上不是 onenote 应用，请核对桥接端口');
    }
    const { payload } = await api('/notebooks');
    renderNotebooks(payload);
    connected = true;
    setActionsEnabled(true);
    setStatus(
      payload.length ? '已连接应用' : '已连接应用，但还没有笔记本，请先在应用里创建',
      payload.length ? 'ok' : 'bad'
    );
  } catch (err) {
    ui.notebookSelect.replaceChildren();
    setStatus(friendlyError(err), 'bad');
  }
}

function renderNotebooks(notebooks) {
  ui.notebookSelect.replaceChildren();
  for (const notebook of notebooks) {
    const option = document.createElement('option');
    option.value = notebook.id;
    option.textContent = notebook.name;
    ui.notebookSelect.appendChild(option);
  }
  if (!notebooks.length) {
    return;
  }
  const remembered = notebooks.find((n) => n.id === config.lastNotebookId);
  ui.notebookSelect.value = remembered ? remembered.id : notebooks[0].id;
}

async function activeTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab || !tab.id) {
    throw new Error('找不到当前标签页');
  }
  if (!/^https?:/.test(tab.url || '')) {
    throw new Error('当前页面不支持剪藏（仅支持 http/https 网页）');
  }
  return tab;
}

async function clip(mode) {
  if (busy || !connected) {
    return;
  }
  busy = true;
  setActionsEnabled(false);
  setResult(ui.result, '正在剪藏…');
  try {
    const tab = await activeTab();
    const notebookId = ui.notebookSelect.value;
    if (!notebookId) {
      throw new Error('请先在应用里创建笔记本');
    }
    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      files: [
        'lib/readability.js',
        'lib/turndown.js',
        'lib/turndown_plugin_gfm.js',
        'content_clip.js',
      ],
    });
    const [result] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: (m) => window.__onenoteClipExtract(m),
      args: [mode],
    });
    const extracted = result && result.result;
    if (!extracted) {
      throw new Error('页面内容提取失败，请刷新页面后重试');
    }
    if (extracted.error) {
      throw new Error(extracted.error);
    }
    await sendClip({
      notebookId,
      title: ui.titleInput.value.trim() || extracted.title,
      markdown: extracted.markdown,
      sourceUrl: extracted.url,
    });
  } catch (err) {
    setResult(ui.result, friendlyError(err), 'bad');
  } finally {
    busy = false;
    setActionsEnabled(connected);
  }
}

function showSettings(show) {
  ui.mainView.hidden = show;
  ui.settingsView.hidden = !show;
  if (show) {
    ui.portInput.value = String(config.port);
    ui.tokenInput.value = config.token;
    ui.portError.hidden = true;
    setResult(ui.settingsResult, '');
    ui.portInput.focus();
  }
}

async function saveSettings() {
  const port = Number(ui.portInput.value.trim());
  if (!Number.isInteger(port) || port < 1024 || port > 65535) {
    ui.portError.hidden = false;
    ui.portInput.focus();
    return;
  }
  ui.portError.hidden = true;
  config.port = port;
  config.token = ui.tokenInput.value.trim();
  await chrome.storage.local.set({ clipPort: port, clipToken: config.token });
  showSettings(false);
  await refreshConnection();
}

ui.openSettings.addEventListener('click', () => showSettings(true));
ui.closeSettings.addEventListener('click', () => showSettings(false));
ui.saveSettings.addEventListener('click', () => {
  void saveSettings();
});
ui.toggleToken.addEventListener('click', () => {
  const showing = ui.tokenInput.type === 'text';
  ui.tokenInput.type = showing ? 'password' : 'text';
  ui.toggleToken.setAttribute('aria-pressed', String(!showing));
  ui.toggleToken.setAttribute('aria-label', showing ? '显示令牌' : '隐藏令牌');
});
ui.clipArticle.addEventListener('click', () => {
  void clip('article');
});
ui.clipSelection.addEventListener('click', () => {
  void clip('selection');
});
ui.clipFullpage.addEventListener('click', () => {
  void clipFullpage();
});
ui.clipShot.addEventListener('click', () => {
  void clipShot();
});
ui.clipBookmark.addEventListener('click', () => {
  void clip('bookmark');
});

void loadConfig().then(async () => {
  await prefillTitle();
  await refreshConnection();
});