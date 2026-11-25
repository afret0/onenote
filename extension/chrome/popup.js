const DEFAULT_PORT = 41190;
const REQUEST_TIMEOUT_MS = 15000;

const ui = {
  mainView: document.getElementById('mainView'),
  settingsView: document.getElementById('settingsView'),
  connStatus: document.getElementById('connStatus'),
  notebookSelect: document.getElementById('notebookSelect'),
  clipArticle: document.getElementById('clipArticle'),
  clipSelection: document.getElementById('clipSelection'),
  clipBookmark: document.getElementById('clipBookmark'),
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
  ui.clipBookmark.disabled = !usable;
  ui.notebookSelect.disabled = !usable;
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
    const { payload } = await api('/clips', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: {
        notebookId,
        title: extracted.title,
        markdown: extracted.markdown,
        sourceUrl: extracted.url,
      },
    });
    config.lastNotebookId = notebookId;
    await chrome.storage.local.set({ lastNotebookId: notebookId });
    const name =
      ui.notebookSelect.selectedOptions[0]?.textContent || '笔记本';
    setResult(ui.result, `已存入「${name}」：${payload.title || '无标题'}`, 'ok');
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
ui.clipBookmark.addEventListener('click', () => {
  void clip('bookmark');
});

void loadConfig().then(refreshConnection);