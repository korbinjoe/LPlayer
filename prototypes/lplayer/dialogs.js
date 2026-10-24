(() => {
  'use strict';

  const defaults = { hand: 'left', theme: 'dark', subtitles: true, private: false, speed: 1, volume: 70, motion: true, previews: true, brandFont: 'manrope' };
  const dialogState = { open: false, kind: 'settings', tab: 'general', query: '', restoreFocus: null, bodyOverflow: '' };
  let root;
  let helpRoot;

  const escapeHTML = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
  const getState = () => ({ ...defaults, ...(window.LPlayerUI?.getState?.() || {}) });
  const icon = (name, className = '') => `<img class="lpdlg-icon ${className}" src="assets/icons/${name}.svg" alt="" draggable="false">`;
  const key = value => `<kbd class="lpdlg-key${String(value).length > 2 ? ' lpdlg-key-wide' : ''}">${escapeHTML(value)}</kbd>`;
  const keys = values => `<span class="lpdlg-keys">${values.map(key).join('<span class="lpdlg-key-separator">/</span>')}</span>`;

  function shortcutGroups(hand) {
    const left = hand !== 'right';
    return [
      { title: '播放与跳转', rows: [
        { label: '播放 / 暂停', keys: ['Space'], terms: '播放 暂停 空格 play pause' },
        { label: '后退 / 前进', keys: left ? ['A', 'D'] : ['J', 'L'], terms: '后退 前进 跳转 seek' },
        { label: '上一个 / 下一个视频', keys: left ? ['W / ↑', 'S / ↓'] : ['I / ↑', 'K / ↓'], terms: '上一 下一 切换 视频 方向键 previous next video' },
        { label: '恢复正常速度', keys: [left ? 'R' : 'P'], terms: '倍速 正常 复原 reset speed' }
      ] },
      { title: '音量与速度', rows: [
        { label: '降低 / 提高音量', keys: left ? ['⇧ S / ⇧ ↓', '⇧ W / ⇧ ↑'] : ['⇧ K / ⇧ ↓', '⇧ I / ⇧ ↑'], terms: '音量 Shift 方向键 volume' },
        { label: '减慢 / 加快播放', keys: left ? ['Q', 'E'] : ['U', 'O'], terms: '倍速 速度 speed' }
      ] },
      { title: '画面与字幕', rows: [
        { label: '进入 / 退出全屏', keys: [left ? 'F' : 'H'], terms: '全屏 fullscreen' },
        { label: '显示 / 隐藏字幕', keys: [left ? 'G' : ';'], terms: '字幕 subtitle' },
        { label: '画面适应窗口', keys: ['0'], terms: '画面 缩放 复原 适应 zoom' }
      ] },
      { title: '文件与面板', rows: [
        { label: '播放列表', keys: [left ? 'T' : "'"], terms: '播放列表 playlist' },
        { label: '快捷面板', keys: [left ? 'C' : ','], terms: '快捷面板 控制 quick controls' },
        { label: '快捷键帮助', keys: [left ? 'V' : 'Y'], terms: '帮助 快捷键 help' },
        { label: '列表首项 / 末项', keys: ['Home', 'End'], terms: '列表 首项 末项 首尾 home end' },
        { label: '打开视频', keys: ['⌘ O'], terms: '文件 打开 open' },
        { label: '设置', keys: ['⌘ ,'], terms: '设置 settings' }
      ] }
    ];
  }

  function ensureRoot() {
    if (root) return root;
    root = document.createElement('div');
    root.id = 'lp-dialog-root';
    root.className = 'lpdlg-root';
    root.hidden = true;
    document.body.append(root);
    root.addEventListener('click', handleClick);
    root.addEventListener('change', handleChange);
    root.addEventListener('input', handleInput);
    ['pointerdown', 'pointerup', 'dblclick', 'wheel'].forEach(type => root.addEventListener(type, event => event.stopPropagation()));
    document.addEventListener('keydown', handleKeyDown, true);
    ['keyup', 'keypress'].forEach(type => document.addEventListener(type, event => {
      if (dialogState.open) event.stopImmediatePropagation();
    }, true));
    return root;
  }

  function segment(label, pref, options, value) {
    return `<div class="lpdlg-segment" role="radiogroup" aria-label="${escapeHTML(label)}">${options.map(option => `
      <button class="lpdlg-segment-item${value === option.value ? ' is-selected' : ''}" type="button" role="radio" aria-checked="${value === option.value}" data-lpdlg-pref="${pref}" data-lpdlg-value="${option.value}" data-focus-key="${pref}-${option.value}">${escapeHTML(option.label)}</button>`).join('')}
    </div>`;
  }

  function toggle(label, pref, checked, invert = false) {
    return `<button type="button" class="lpdlg-switch${checked ? ' is-on' : ''}" role="switch" aria-label="${escapeHTML(label)}" aria-checked="${checked}" data-lpdlg-toggle="${pref}"${invert ? ' data-lpdlg-invert="true"' : ''} data-focus-key="${pref}"><span class="lpdlg-switch-thumb"></span></button>`;
  }

  function row(title, description, control, extra = '') {
    return `<div class="lpdlg-form-row ${extra}"><div class="lpdlg-row-text"><span class="lpdlg-row-title">${title}</span>${description ? `<span class="lpdlg-row-description">${description}</span>` : ''}</div><div class="lpdlg-row-control">${control}</div></div>`;
  }

  function group(title, content, footnote = '') {
    return `<section class="lpdlg-form-section"><h3 class="lpdlg-section-label">${title}</h3><div class="lpdlg-form-group">${content}</div>${footnote ? `<p class="lpdlg-footnote">${footnote}</p>` : ''}</section>`;
  }

  function generalContent(state) {
    return `<div class="lpdlg-page-intro"><h2>通用</h2><p>让播放器更合你的习惯。</p></div>
      ${group('外观与操作',
        row('界面外观', '', segment('界面外观', 'theme', [{ value: 'dark', label: '深色' }, { value: 'light', label: '浅色' }], state.theme)) +
        row('单手布局', '', segment('单手布局', 'hand', [{ value: 'left', label: '左手' }, { value: 'right', label: '右手' }], state.hand)),
        '单手快捷键随布局切换，空格键始终用于播放与暂停。')}
      ${group('辅助使用', row('减少动效', '缩短界面切换和浮层动画', toggle('减少动效', 'motion', !state.motion, true)))}
      <div class="lpdlg-inline-tip">${icon('keyboard')}<span>查看当前布局的快捷键</span><button type="button" data-lpdlg-tab="shortcuts" data-focus-key="show-shortcuts">查看<span aria-hidden="true">›</span></button></div>`;
  }

  function typographyContent(state) {
    const fonts = [
      {id:'manrope', name:'Manrope', css:'LP Manrope', description:'克制、清晰，偏精致工具感'},
      {id:'outfit', name:'Outfit', css:'LP Outfit', description:'圆润、亲和，偏影音品牌感'},
      {id:'space', name:'Space Grotesk', css:'LP Space Grotesk', description:'结构鲜明，偏技术与个性'}
    ];
    return `<div class="lpdlg-page-intro"><h2>品牌字体</h2><p>为 LPlayer 选择更有辨识度的英文标识。</p></div>
      <div class="lpdlg-wordmark-preview"><img src="assets/app-icon.png" alt=""><span class="brand-wordmark">LPlayer</span></div>
      <div class="lpdlg-font-list" role="radiogroup" aria-label="品牌字体">${fonts.map(font=>`<button class="lpdlg-font-choice${state.brandFont===font.id?' is-selected':''}" role="radio" aria-checked="${state.brandFont===font.id}" aria-label="${font.name}" data-lpdlg-pref="brandFont" data-lpdlg-value="${font.id}" data-focus-key="brandFont-${font.id}"><span class="lpdlg-font-specimen" style="--specimen-font:'${font.css}'">LPlayer</span><span class="lpdlg-font-meta"><strong>${font.name}</strong><small>${font.description}</small></span><img class="lpdlg-font-check" src="assets/icons/check.svg" alt=""></button>`).join('')}</div>
      <p class="lpdlg-font-note">字标即时更新。中文界面、功能标签和时间读数使用系统字体。</p>`;
  }

  function playbackContent(state) {
    const speeds = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3];
    if (!speeds.some(speed => Math.abs(speed - Number(state.speed)) < 0.001)) speeds.push(Number(state.speed));
    speeds.sort((a, b) => a - b);
    return `<div class="lpdlg-page-intro"><h2>播放</h2><p>将注意力留给正在看的内容。</p></div>
      ${group('播放偏好',
        row('默认播放速度', '', `<select class="lpdlg-select" aria-label="默认播放速度" data-lpdlg-pref="speed" data-focus-key="speed">${speeds.map(speed => `<option value="${speed}"${Number(state.speed) === speed ? ' selected' : ''}>${speed === 1 ? '正常 · 1×' : speed + '×'}</option>`).join('')}</select>`) +
        row('显示字幕', '播放时显示可用的字幕', toggle('显示字幕', 'subtitles', state.subtitles)) +
        row('静音预览', '在列表中预览视频画面', toggle('静音预览', 'previews', state.previews)))}
      ${group('隐私', row('无痕模式', '不保留本次观看记录', toggle('无痕模式', 'private', state.private)))}
      <p class="lpdlg-bottom-note">播放中的速度与字幕也可以随时在快捷面板中调整。</p>`;
  }

  function shortcutList(state, query = '', help = false) {
    const needle = query.trim().toLocaleLowerCase();
    const groups = shortcutGroups(state.hand).map(item => ({ ...item, rows: item.rows.filter(itemRow => !needle || `${itemRow.label} ${itemRow.keys.join(' ')} ${itemRow.terms}`.toLocaleLowerCase().includes(needle)) })).filter(item => item.rows.length);
    if (!groups.length) return `<div class="lpdlg-no-results">${icon('keyboard')}<strong>没有找到相关快捷键</strong><span>试试“字幕”“音量”或按键名称。</span></div>`;
    return `<div class="${help ? 'lpdlg-help-grid' : 'lpdlg-shortcut-groups'}">${groups.map(item => `<section class="lpdlg-shortcut-section"><h3 class="lpdlg-section-label">${item.title}</h3><div class="lpdlg-shortcut-group">${item.rows.map(itemRow => `<div class="lpdlg-shortcut-row"><span>${escapeHTML(itemRow.label)}</span>${keys(itemRow.keys)}</div>`).join('')}</div></section>`).join('')}</div>`;
  }

  function shortcutsContent(state) {
    return `<div class="lpdlg-page-intro lpdlg-page-intro-shortcuts"><h2>快捷键</h2><p>${state.hand === 'right' ? '右手' : '左手'}布局，熟悉的操作就在指尖。</p></div>
      <label class="lpdlg-search"><span class="lpdlg-search-symbol" aria-hidden="true"></span><input id="lpdlg-shortcut-search" type="search" placeholder="搜索快捷键" aria-label="搜索快捷键" value="${escapeHTML(dialogState.query)}" autocomplete="off" data-focus-key="shortcut-search"><span class="lpdlg-search-escape" aria-hidden="true">搜索</span></label>
      <div id="lpdlg-shortcut-results" aria-live="polite">${shortcutList(state, dialogState.query)}</div>
      <p class="lpdlg-bottom-note">默认键位展示；自定义录制在原生 App 中使用，HTML 不模拟。列表可见时保持列表导航，Esc 收起。</p>`;
  }

  function settingsMarkup(state) {
    const tabs = [{ id: 'general', name: '通用', icon: 'gear-six' }, { id: 'typography', name: '品牌字体', icon: 'text-aa' }, { id: 'playback', name: '播放', icon: 'play-fill' }, { id: 'shortcuts', name: '快捷键', icon: 'keyboard' }];
    const content = dialogState.tab === 'typography' ? typographyContent(state) : dialogState.tab === 'playback' ? playbackContent(state) : dialogState.tab === 'shortcuts' ? shortcutsContent(state) : generalContent(state);
    return `<section class="lpdlg-sheet lpdlg-settings" role="dialog" aria-modal="true" aria-label="LPlayer 设置" data-lpdlg="settings">
      <aside class="lpdlg-sidebar"><div class="lpdlg-brand"><img class="lpdlg-brand-logo" src="assets/app-icon.png" alt=""><div><strong>LPlayer</strong><span>设置</span></div></div>
        <nav class="lpdlg-navigation" role="tablist" aria-label="设置类别" aria-orientation="vertical">${tabs.map(tab => `<button type="button" role="tab" class="lpdlg-nav-item${dialogState.tab === tab.id ? ' is-active' : ''}" aria-selected="${dialogState.tab === tab.id}" aria-controls="lpdlg-settings-panel" data-lpdlg-tab="${tab.id}" data-focus-key="tab-${tab.id}"><span class="lpdlg-nav-icon lpdlg-nav-icon-${tab.id}">${icon(tab.icon)}</span>${tab.name}</button>`).join('')}</nav>
        <span class="lpdlg-sidebar-caption">为专注观看而设</span>
      </aside>
      <div class="lpdlg-settings-main"><button type="button" class="lpdlg-close" aria-label="关闭设置" data-lpdlg-close data-focus-key="close">${icon('x')}</button><div id="lpdlg-settings-panel" class="lpdlg-pane" role="tabpanel" tabindex="-1">${content}</div><footer class="lpdlg-footer"><span>更改会立即生效</span><button class="lpdlg-done" type="button" data-lpdlg-close data-focus-key="done">完成</button></footer></div>
    </section>`;
  }

  function helpMarkup(state) {
    const left = state.hand !== 'right';
    const navigation = left ? 'W/S 选择 · A/D 调整' : 'I/K 选择 · J/L 调整';
    const helpKeys = values => `<span class="lphelp-keys">${values.map(value => `<kbd>${escapeHTML(value)}</kbd>`).join('<span class="lphelp-key-separator">/</span>')}</span>`;
    const groups = shortcutGroups(state.hand).map(group => `<section class="lphelp-group"><h3>${group.title}</h3><div class="lphelp-rows">${group.rows.map(row => `<div class="lphelp-row"><span>${row.label}</span>${helpKeys(row.keys)}</div>`).join('')}</div></section>`).join('');
    return `<header class="lphelp-header"><h2>快捷键</h2><p>${left ? '左手' : '右手'}布局 · 边看边操作</p><button type="button" class="lphelp-close" aria-label="收起快捷键帮助" title="${left ? 'V' : 'Y'} / Esc 收起" data-lphelp-close><span class="icon" style="--icon:url('assets/icons/x.svg')" aria-hidden="true"></span></button></header>
      <div class="lphelp-content">${groups}<p class="lphelp-caption">列表与快捷面板：${navigation}，Space / Enter 确认。列表内左右键不会跳转主视频。</p><p class="lphelp-caption">双指缩放、双指轻点与移动画面仅在原生 App 中实现；网页不模拟这些触控板手势。</p></div>
      <footer class="lphelp-footer"><button type="button" data-lphelp-settings>快捷键设置…</button><p>${left ? 'V' : 'Y'} / Esc 收起 · 播放快捷键仍可使用</p></footer>`;
  }

  function ensureHelp() {
    if (helpRoot) return helpRoot;
    helpRoot = document.createElement('aside');
    helpRoot.id = 'lp-help-rail';
    helpRoot.className = 'help-rail';
    helpRoot.hidden = true;
    helpRoot.setAttribute('aria-label', '快捷键帮助');
    document.querySelector('.workspace').append(helpRoot);
    helpRoot.addEventListener('click', event => {
      if (event.target.closest('[data-lphelp-close]')) closeHelp();
      else if (event.target.closest('[data-lphelp-settings]')) {
        if (window.LPlayerUI?.openSettings) window.LPlayerUI.openSettings('shortcuts');
        else open('settings', 'shortcuts');
      }
    });
    return helpRoot;
  }

  function refreshHelp() {
    if (!helpRoot || helpRoot.hidden) return;
    const top = helpRoot.querySelector('.lphelp-content')?.scrollTop || 0;
    helpRoot.innerHTML = helpMarkup(getState());
    helpRoot.querySelector('.lphelp-content').scrollTop = top;
  }

  function openHelp() {
    if (dialogState.open) return;
    window.LPlayerUI?.prepareHelp?.();
    const element = ensureHelp();
    element.hidden = false;
    refreshHelp();
    window.LPlayerUI?.onHelpChange?.();
  }

  function closeHelp() {
    if (!helpRoot || helpRoot.hidden) return;
    const hadFocus = helpRoot.contains(document.activeElement);
    helpRoot.hidden = true;
    if (hadFocus) document.getElementById('stage')?.focus({ preventScroll: true });
    window.LPlayerUI?.onHelpChange?.();
  }

  function render(preserveFocus = false) {
    const element = ensureRoot();
    const state = getState();
    const focused = preserveFocus && element.contains(document.activeElement) ? document.activeElement : null;
    const focusKey = focused?.dataset?.focusKey;
    const selectionStart = focused?.selectionStart;
    const scrollTop = element.querySelector('.lpdlg-pane')?.scrollTop || 0;
    element.classList.toggle('lpdlg-light', state.theme === 'light');
    element.classList.toggle('lpdlg-reduced-motion', !state.motion);
    element.classList.toggle('lpdlg-updating', preserveFocus);
    element.innerHTML = settingsMarkup(state);
    if (preserveFocus) {
      const newPane = element.querySelector('.lpdlg-pane');
      if (newPane) newPane.scrollTop = scrollTop;
      if (focusKey) {
        const next = [...element.querySelectorAll('[data-focus-key]')].find(candidate => candidate.dataset.focusKey === focusKey);
        next?.focus({ preventScroll: true });
        if (typeof selectionStart === 'number' && next?.setSelectionRange) {
          try { next.setSelectionRange(selectionStart, selectionStart); } catch (_) { /* Select controls do not expose text selection. */ }
        }
      }
    }
  }

  function open(kind, tab = 'general') {
    closeHelp();
    ensureRoot();
    if (!dialogState.open) {
      dialogState.restoreFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
      dialogState.bodyOverflow = document.body.style.overflow;
      document.body.style.overflow = 'hidden';
    }
    dialogState.open = true;
    dialogState.kind = kind;
    dialogState.tab = ['general', 'typography', 'playback', 'shortcuts'].includes(tab) ? tab : 'general';
    dialogState.query = '';
    root.hidden = false;
    render();
    requestAnimationFrame(() => {
      if (!dialogState.open) return;
      const first = root.querySelector(`[data-lpdlg-tab="${dialogState.tab}"]`);
      first?.focus({ preventScroll: true });
    });
  }

  function close() {
    if (!dialogState.open) { closeHelp(); return; }
    dialogState.open = false;
    root.hidden = true;
    document.body.style.overflow = dialogState.bodyOverflow;
    const previous = dialogState.restoreFocus;
    dialogState.restoreFocus = null;
    if (previous?.isConnected) previous.focus({ preventScroll: true });
  }

  function setPreference(pref, value) {
    const ui = window.LPlayerUI;
    if (typeof ui?.setPreference !== 'function') return;
    ui.setPreference(pref, value);
    render(true);
  }

  function handleClick(event) {
    if (!dialogState.open) return;
    event.stopPropagation();
    if (event.target === root) { close(); return; }
    const button = event.target.closest('button');
    if (!button) return;
    if (button.hasAttribute('data-lpdlg-close')) { close(); return; }
    if (button.hasAttribute('data-lpdlg-open-general')) { open('settings', 'general'); return; }
    if (button.dataset.lpdlgTab) {
      dialogState.tab = button.dataset.lpdlgTab;
      dialogState.query = '';
      render(true);
      root.querySelector(`[data-lpdlg-tab="${dialogState.tab}"]`)?.focus({ preventScroll: true });
      return;
    }
    if (button.dataset.lpdlgPref) { setPreference(button.dataset.lpdlgPref, button.dataset.lpdlgValue); return; }
    if (button.dataset.lpdlgToggle) {
      const pref = button.dataset.lpdlgToggle;
      setPreference(pref, !getState()[pref]);
    }
  }

  function handleChange(event) {
    event.stopPropagation();
    if (event.target.matches('select[data-lpdlg-pref]')) setPreference(event.target.dataset.lpdlgPref, Number(event.target.value));
  }

  function handleInput(event) {
    event.stopPropagation();
    if (event.target.id !== 'lpdlg-shortcut-search') return;
    dialogState.query = event.target.value;
    root.querySelector('#lpdlg-shortcut-results').innerHTML = shortcutList(getState(), dialogState.query);
  }

  function handleKeyDown(event) {
    if (!dialogState.open) return;
    event.stopImmediatePropagation();
    if (event.key === 'Escape' && !event.metaKey && !event.ctrlKey && !event.altKey) { event.preventDefault(); close(); return; }
    if (event.metaKey || event.ctrlKey || event.altKey) return;
    const radioGroup = event.target.closest?.('[role="radiogroup"]');
    if (radioGroup && ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(event.key)) {
      event.preventDefault();
      const options = [...radioGroup.querySelectorAll('[role="radio"]')];
      const index = options.indexOf(event.target);
      const direction = ['ArrowLeft', 'ArrowUp'].includes(event.key) ? -1 : 1;
      const next = options[(index + direction + options.length) % options.length];
      const focusKey = next.dataset.focusKey;
      next.click();
      [...root.querySelectorAll('[data-focus-key]')].find(candidate => candidate.dataset.focusKey === focusKey)?.focus({ preventScroll: true });
      return;
    }
    const tab = event.target.closest?.('[role="tab"]');
    if (tab && ['ArrowUp', 'ArrowDown'].includes(event.key)) {
      event.preventDefault();
      const tabs = [...root.querySelectorAll('[role="tab"]')];
      tabs[(tabs.indexOf(tab) + (event.key === 'ArrowUp' ? -1 : 1) + tabs.length) % tabs.length].click();
      return;
    }
    if (event.key !== 'Tab') return;
    const focusable = [...root.querySelectorAll('button:not([disabled]), input:not([disabled]), select:not([disabled]), [tabindex="0"]')].filter(element => element.getClientRects().length);
    if (!focusable.length) { event.preventDefault(); return; }
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (!root.contains(document.activeElement)) { event.preventDefault(); first.focus(); }
    else if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
  }

  window.LPlayerDialogs = {
    openSettings(tab = 'general') { open('settings', tab); },
    openHelp,
    closeHelp,
    refreshHelp,
    isHelpOpen() { return Boolean(helpRoot && !helpRoot.hidden); },
    close,
    isOpen() { return dialogState.open; }
  };
})();
