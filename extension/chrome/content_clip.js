(() => {
  function absolutize(root, baseUrl) {
    for (const el of root.querySelectorAll('img')) {
      const src = el.getAttribute('src');
      if (src) {
        try {
          el.setAttribute('src', new URL(src, baseUrl).href);
        } catch (err) {
          el.removeAttribute('src');
        }
      }
      el.removeAttribute('srcset');
      const lazy = el.getAttribute('data-src') || el.getAttribute('data-original');
      if (!el.getAttribute('src') && lazy) {
        try {
          el.setAttribute('src', new URL(lazy, baseUrl).href);
        } catch (err) {
          el.removeAttribute('src');
        }
      }
    }
    for (const el of root.querySelectorAll('a[href]')) {
      try {
        el.setAttribute('href', new URL(el.getAttribute('href'), baseUrl).href);
      } catch (err) {
        el.removeAttribute('href');
      }
    }
  }

  function toMarkdown(container, baseUrl) {
    absolutize(container, baseUrl);
    const service = new TurndownService({
      headingStyle: 'atx',
      hr: '---',
      bulletListMarker: '-',
      codeBlockStyle: 'fenced',
      emDelimiter: '*',
    });
    service.use(turndownPluginGfm.gfm);
    return service.turndown(container).trim();
  }

  function selectionContainer() {
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
      return null;
    }
    const container = document.createElement('div');
    for (let i = 0; i < selection.rangeCount; i++) {
      container.appendChild(selection.getRangeAt(i).cloneContents());
    }
    const hasContent =
      container.textContent.trim() || container.querySelector('img');
    return hasContent ? container : null;
  }

  function extract(mode) {
    const payload = {
      title: document.title || location.href,
      url: location.href,
      markdown: '',
    };
    if (mode === 'bookmark') {
      return payload;
    }
    if (mode === 'selection') {
      const container = selectionContainer();
      if (!container) {
        return { error: '请先在页面上选中要剪藏的内容' };
      }
      payload.markdown = toMarkdown(container, location.href);
      if (!payload.markdown) {
        return { error: '选中内容转换后为空' };
      }
      return payload;
    }
    const clone = document.cloneNode(true);
    let article = null;
    try {
      article = new Readability(clone).parse();
    } catch (err) {
      article = null;
    }
    if (article && article.content) {
      const container = document.createElement('div');
      container.innerHTML = article.content;
      if (article.title) {
        payload.title = article.title;
      }
      payload.markdown = toMarkdown(container, location.href);
    }
    if (!payload.markdown) {
      const fallback = document.body.cloneNode(true);
      for (const el of fallback.querySelectorAll(
        'script, style, noscript, iframe, nav, header, footer, aside'
      )) {
        el.remove();
      }
      payload.markdown = toMarkdown(fallback, location.href);
    }
    if (!payload.markdown) {
      return { error: '未能提取到页面内容，可改用「收藏网址」' };
    }
    return payload;
  }

  window.__onenoteClipExtract = extract;
})();