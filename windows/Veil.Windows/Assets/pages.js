// Show script errors on the page instead of leaving it blank.
function showErr(err) {
  try {
    const pre = document.createElement('pre');
    pre.style.cssText = 'padding:24px;white-space:pre-wrap;color:#f08080;font:13px Consolas,monospace';
    pre.textContent = 'Page error:\n' + ((err && err.stack) || err);
    (document.getElementById('app') || document.body).replaceChildren(pre);
  } catch (_) {}
}
window.addEventListener('error', e => showErr(e.error || e.message));
window.addEventListener('unhandledrejection', e => showErr(e.reason));
const $ = (s, r = document) => r.querySelector(s);
const h = (tag, props, ...kids) => {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (k === 'class') e.className = v;
    else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else if (k in e) e[k] = v;
    else e.setAttribute(k, v);
  }
  for (const kid of kids.flat()) if (kid != null && kid !== false) e.append(kid.nodeType ? kid : document.createTextNode(kid));
  return e;
};
const call = (() => { let n = 0; const waits = new Map();
      window.chrome.webview.addEventListener('message', e => { const m = e.data; const w = m && waits.get(m.id); if (w) { waits.delete(m.id); w(m.result); } });
      return (cmd, args = {}) => new Promise(res => { const id = ++n; waits.set(id, res); window.chrome.webview.postMessage({ id, cmd, args });
        if (cmd !== 'lists.update') setTimeout(() => { if (waits.delete(id)) res(null); }, 10000); });
    })();
const fmt = ts => new Date(ts * 1000).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
const root = document.getElementById('app');
const page = document.body.dataset.page;
const ACCENTS = { mist: ['#8fb3c9', '#3d6c8a'], coral: ['#f0907d', '#c4503a'], mint: ['#6fd0a8', '#26896a'], violet: ['#ab94f5', '#6f52c9'], amber: ['#e8b058', '#a8700f'], pink: ['#f48fbe', '#be3c78'], sky: ['#64b5f6', '#1976d2'], lime: ['#aad65c', '#628c14'], crimson: ['#e8646e', '#b02838'] };
const applyAccent = name => {
  const dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  const a = ACCENTS[name] || ACCENTS.mist;
  document.documentElement.style.setProperty('--accent', dark ? a[0] : a[1]);
};
// replaceChildren turns null into the text "null", so always drop empty values first.
const put = (el, ...kids) => el.replaceChildren(...kids.flat().filter(k => k != null && k !== false));
const NAV = [['settings', 'Settings'], ['privacy', 'Privacy'], ['history', 'History'], ['bookmarks', 'Bookmarks'], ['downloads', 'Downloads']];

function shell(title, ...body) {
  document.title = title;
  root.replaceChildren(
    h('nav', {}, h('div', { class: 'brand' }, 'Veil'),
      ...NAV.map(([id, label]) => h('a', { href: 'veil://' + id, class: id === page ? 'on' : '' }, label))),
    h('main', {}, h('h1', {}, title), ...body));
}
const empty = msg => h('div', { class: 'empty' }, msg);
const sw = (checked, onchange) => h('label', { class: 'sw' }, h('input', { type: 'checkbox', checked, onchange: e => onchange(e.target.checked) }), h('span'));
const row = (label, hint, control) => h('div', { class: 'row' }, h('div', {}, h('div', { class: 'l' }, label), hint ? h('div', { class: 'hint' }, hint) : null), control);

async function settingsPage() {
  const st = await call('settings.get');
  const s = st.settings;
  const nt = s.newTab;
  const set = (k, v) => { s[k] = v; return call('settings.set', { key: k, value: v }); };
  const saveNT = () => call('settings.set', { key: 'newTab', value: nt });
  const toggle = (key, label, hint) => row(label, hint, sw(s[key], v => set(key, v)));
  const ntToggle = (key, label, hint) => row(label, hint, sw(nt[key], v => { nt[key] = v; saveNT(); }));
  // Veil's own dropdown (instead of the system select box)
  const dropdown = (opts, cur, pick) => {
    const found = opts.find(o => o[0] === cur) || opts[0];
    const label = h('span', {}, found[1]);
    const list = h('div', { class: 'ddl' });
    const box = h('div', { class: 'dd' });
    const away = e => { if (!box.contains(e.target)) close(); };
    const close = () => { box.classList.remove('open'); document.removeEventListener('mousedown', away, true); };
    opts.forEach(([v, l]) => {
      const item = h('div', { class: 'ddi' + (v === found[0] ? ' on' : '') }, l);
      item.addEventListener('click', () => {
        Array.from(list.children).forEach(c => c.classList.toggle('on', c === item));
        label.textContent = l;
        close();
        pick(v);
      });
      list.append(item);
    });
    const btn = h('button', { class: 'ddb', type: 'button' }, label, h('span', { class: 'caret' }, '▾'));
    btn.addEventListener('click', () => {
      if (box.classList.contains('open')) { close(); return; }
      document.querySelectorAll('.dd.open').forEach(d => d.classList.remove('open'));
      box.classList.add('open');
      document.addEventListener('mousedown', away, true);
    });
    box.append(btn, list);
    return box;
  };
  const select = (key, opts) => dropdown(opts, s[key], v => set(key, v));
  const ntSelect = (key, opts) => dropdown(opts, nt[key], v => { nt[key] = v; saveNT(); });
  const status = h('span', { class: 'mute' });
  const picStatus = h('span', { class: 'mute' }, nt.customImage ? 'Picture saved' : '');
  const swatches = h('div', { class: 'swatches' });
  Object.keys(ACCENTS).forEach(name => {
    const b = h('button', { class: 'swatch' + (s.accent === name ? ' on' : ''), title: name, style: 'background:' + ACCENTS[name][0],
      onclick: () => { set('accent', name); applyAccent(name); swatches.querySelectorAll('.swatch').forEach(x => x.classList.toggle('on', x === b)); } });
    swatches.append(b);
  });

  // Browser themes (tab bar, toolbar and address box colours)
  const THEMES = { default: ['Default', null], midnight: ['Midnight', [222, .60]], forest: ['Forest', [140, .45]], rose: ['Rose', [340, .50]],
    sunset: ['Sunset', [18, .62]], grape: ['Grape', [272, .50]], ocean: ['Ocean', [190, .58]], mocha: ['Mocha', [28, .35]],
    mint: ['Mint', [160, .48]], graphite: ['Graphite', [220, 0]] };
  const hsb = (hh, ss, vv) => {
    const f = n => { const k = (n + hh / 60) % 6; return vv - vv * ss * Math.max(0, Math.min(k, 4 - k, 1)); };
    return '#' + [f(5), f(3), f(1)].map(x => Math.round(x * 255).toString(16).padStart(2, '0')).join('');
  };
  const themeGrid = h('div', { class: 'themes' });
  Object.keys(THEMES).forEach(key => {
    const label = THEMES[key][0], hs = THEMES[key][1];
    const bar = hs ? hsb(hs[0], hs[1], .16) : '#131417';
    const chip = hs ? hsb(hs[0], hs[1] * .8, .31) : '#2c2f37';
    const b = h('button', { class: 'tsw' + ((s.browserTheme || 'default') === key ? ' on' : ''), title: label,
      onclick: () => { set('browserTheme', key); themeGrid.querySelectorAll('.tsw').forEach(x => x.classList.toggle('on', x === b)); } },
      h('div', { class: 'tbar', style: 'background:' + bar }, h('i', { style: 'background:' + chip })), h('span', {}, label));
    themeGrid.append(b);
  });

  const picker = h('input', { type: 'file', accept: 'image/*', style: 'display:none', onchange: e => {
    const f = e.target.files[0]; if (!f) return;
    const reader = new FileReader();
    reader.onload = () => {
      const img = new Image();
      img.onload = async () => {
        const k = Math.min(1, 1920 / Math.max(img.width, img.height));
        const c = document.createElement('canvas');
        c.width = Math.max(1, Math.round(img.width * k)); c.height = Math.max(1, Math.round(img.height * k));
        c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
        const ok = await call('background.set', { data: c.toDataURL('image/jpeg', 0.82) });
        if (ok) { nt.background = 'custom'; nt.customImage = true; saveNT(); picStatus.textContent = 'Picture saved. Background set to My picture.'; }
        else picStatus.textContent = 'That picture could not be saved.';
      };
      img.src = reader.result;
    };
    reader.readAsDataURL(f);
  } });

  const excBox = h('textarea', { id: 'exc', spellcheck: false, placeholder: 'example.com', value: (s.cookieExceptions || []).join('\n') });
  const folderLabel = h('span', { class: 'mute' }, s.downloadFolder || 'Downloads');

  const FUN_DEFAULTS = { windowOpacity: 100, alwaysOnTop: false, pageFilter: 'none', pageFont: 'default', linkStyle: 'default',
    selectionColor: 'default', smoothScroll: false, hideScrollbars: false, roundImages: false, blurImages: false, dimPages: 0,
    reduceMotion: false, forceSelect: false, readableText: false, grayImages: false };
  const PRESETS = {
    'Normal': { theme: 'dark', accent: 'mist' },
    'Cozy night': { theme: 'dark', accent: 'amber', dimPages: 10, smoothScroll: true },
    'Neon arcade': { theme: 'dark', accent: 'pink', pageFilter: 'vivid', pageFont: 'rounded', selectionColor: 'lime' },
    'Paper': { theme: 'light', accent: 'mist', pageFont: 'serif', linkStyle: 'highlight', readableText: true },
    'Hacker': { theme: 'dark', accent: 'lime', pageFilter: 'dark', pageFont: 'mono', selectionColor: 'lime', hideScrollbars: true },
    'Candy': { theme: 'light', accent: 'pink', pageFont: 'rounded', selectionColor: 'pink', roundImages: true }
  };
  const LOCKDOWN = { adBlocking: true, cookieMode: 'third-party', httpsUpgrade: true, fingerprintProtection: true, sendGPC: true,
    clearHistoryOnQuit: true, keepSessionCookies: false, blockPopups: true, stripTracking: true, opsecWebRTC: true, opsecBeacons: true,
    opsecReferrer: true, opsecHardware: true, hideFromCapture: true, denyMedia: true };
  const lockdown = async () => {
    for (const k of Object.keys(LOCKDOWN)) await set(k, LOCKDOWN[k]);
    location.reload();
  };
  const applyPreset = async name => {
    const p = Object.assign({}, FUN_DEFAULTS, PRESETS[name]);
    for (const k of Object.keys(p)) await set(k, p[k]);
    location.reload();
  };

  shell('Settings',
    h('h2', {}, 'Look and fun'),
    h('div', { class: 'card' },
      row('Theme', null, select('theme', [['dark', 'Dark'], ['light', 'Light'], ['system', 'Match system']])),
      row('Accent colour', 'Tints tabs, buttons and these pages.', swatches),
      row('Browser theme', 'Colours the tab bar, toolbar and address bar, like Chrome themes.', themeGrid),
      toggle('verticalTabs', 'Vertical tabs', 'Show tabs in a sidebar instead of a row. Shortcut: Ctrl+Shift+\\'),
      row('Tab width', null, select('tabWidth', [['compact', 'Compact'], ['normal', 'Normal'], ['wide', 'Wide']])),
      toggle('showBookmarksBar', 'Show bookmarks bar', 'Keeps the pages you bookmark (Ctrl+D) at the top of every window.')),

    h('h2', {}, 'Quick looks'),
    h('div', { class: 'card' },
      row('Theme presets', 'One click sets the colours, fonts and page style together.',
        h('div', { class: 'actions', style: 'margin:0;flex-wrap:wrap;justify-content:flex-end' },
          ...Object.keys(PRESETS).map(n => h('button', { onclick: () => applyPreset(n) }, n)))),
      row('Reset fun settings', 'Puts everything in Window fun and Web page fun back to normal.',
        h('button', { class: 'danger', onclick: () => applyPreset('Normal') }, 'Reset'))),

    h('h2', {}, 'Tidy up'),
    h('div', { class: 'card' },
      toggle('newTabNextToCurrent', 'Open new tabs next to the current tab', 'Off = new tabs go to the far end.'),
      toggle('rememberWindow', 'Remember window size and position', null),
      toggle('confirmCloseWindow', 'Ask before closing a window with several tabs', null),
      toggle('hideShieldButton', 'Hide the shield button', 'You can still reach it from the privacy page.'),
      toggle('hideDownloadsButton', 'Hide the downloads button', null),
      toggle('hideBookmarkButton', 'Hide the bookmark star', 'The shortcut Ctrl+D still works.')),

    h('h2', {}, 'Window fun'),
    h('div', { class: 'card' },
      row('See-through window', 'Lower = more see-through. Applies right away.', h('input', { type: 'range', min: 60, max: 100, value: s.windowOpacity, onchange: e => set('windowOpacity', Number(e.target.value)) })),
      toggle('alwaysOnTop', 'Keep window on top', 'Veil floats above your other apps.'),
      toggle('dockTabCount', 'Show tab count on the Dock icon', null),
      toggle('confirmQuit', 'Ask before quitting with several tabs open', null),
      toggle('downloadSound', 'Play a sound when a download finishes', null)),

    h('h2', {}, 'Web page fun'),
    h('div', { class: 'card' },
      row('Page style', 'Changes how every website looks. Applies to pages you open or reload.',
        select('pageFilter', [['none', 'Normal'], ['dark', 'Dark mode for every site'], ['grayscale', 'Black and white'], ['sepia', 'Old photo'], ['contrast', 'High contrast'], ['vivid', 'Extra colourful'], ['cool', 'Alien blue']])),
      row('Page font', 'Swap the font on websites.', select('pageFont', [['default', 'Normal'], ['comic', 'Comic'], ['rounded', 'Rounded'], ['serif', 'Serif'], ['mono', 'Typewriter'], ['hand', 'Handwriting']])),
      row('Text highlight colour', 'The colour when you select text.', select('selectionColor', [['default', 'Normal'], ['pink', 'Pink'], ['lime', 'Lime'], ['yellow', 'Yellow'], ['sky', 'Sky blue'], ['violet', 'Violet']])),
      row('Link style', null, select('linkStyle', [['default', 'Normal'], ['wavy', 'Wavy underline'], ['highlight', 'Highlighter'], ['underline', 'Always underlined'], ['plain', 'No underline']])),
      toggle('roundImages', 'Round image corners', null),
      toggle('blurImages', 'Blur images until you point at them', 'Handy when someone is looking over your shoulder.'),
      toggle('smoothScroll', 'Smooth scrolling', null),
      toggle('hideScrollbars', 'Hide scrollbars', null),
      toggle('reduceMotion', 'Calm animations', 'Stops most movement and fades on websites.'),
      toggle('forceSelect', 'Always allow selecting text', 'Works on sites that try to stop you copying.'),
      toggle('readableText', 'Easier-to-read text', 'More space between lines and shorter paragraphs.'),
      toggle('grayImages', 'Black and white images', null),
      row('Dim pages', 'Makes bright websites darker.', h('input', { type: 'range', min: 0, max: 60, value: s.dimPages, onchange: e => set('dimPages', Number(e.target.value)) }))),

    h('h2', {}, 'Start page'),
    h('div', { class: 'card' },
      row('Background', null, ntSelect('background', [['aurora', 'Aurora'], ['poster', 'Poster'], ['plain', 'Plain'], ['grain', 'Soft grain'], ['dusk', 'Dusk'], ['forest', 'Forest'], ['ember', 'Ember'], ['midnight', 'Midnight'], ['paper', 'Paper'], ['ocean', 'Ocean'], ['sunset', 'Sunset'], ['neon', 'Neon'], ['candy', 'Candy'], ['sakura', 'Sakura'], ['custom', 'My picture']])),
      row('My picture', 'Choose any image. It is shrunk and stored only on this PC.', h('div', { class: 'actions', style: 'margin:0' },
        h('button', { onclick: () => picker.click() }, 'Choose…'),
        h('button', { onclick: async () => { await call('background.clear'); nt.customImage = false; if (nt.background === 'custom') nt.background = 'aurora'; saveNT(); picStatus.textContent = 'Picture removed.'; } }, 'Remove'), picker)),
      row('', null, picStatus),
      row('Darken background', 'Makes text easier to read over bright pictures.', h('input', { type: 'range', min: 0, max: 70, value: nt.dim, onchange: e => { nt.dim = Number(e.target.value); saveNT(); } })),
      row('Font', null, ntSelect('font', [['modern', 'Modern'], ['rounded', 'Rounded'], ['serif', 'Serif']])),
      row('Clock size', null, ntSelect('clockSize', [['small', 'Small'], ['medium', 'Medium'], ['large', 'Large']])),
      row('Shortcut style', null, ntSelect('tileStyle', [['rounded', 'Rounded squares'], ['circle', 'Circles'], ['minimal', 'Minimal']])),
      row('Shortcut size', null, ntSelect('tileSize', [['small', 'Small'], ['medium', 'Medium'], ['large', 'Large']])),
      ntToggle('showLabels', 'Show shortcut names', null),
      row('Your name', 'Used in the greeting.', h('input', { type: 'text', value: nt.name, placeholder: 'Name', onchange: e => { nt.name = e.target.value.trim(); saveNT(); } })),
      ntToggle('showClock', 'Show clock', null),
      ntToggle('use24Hour', '24-hour clock', null),
      ntToggle('showSearch', 'Show search box', null),
      ntToggle('animated', 'Animated background', 'A slow, gentle drift. Turn off to save a little power.'),
      ntToggle('funLines', 'Daily one-liner', 'A small line under your shortcuts that changes each day.')),

    h('h2', {}, 'Productivity'),
    h('div', { class: 'card' },
      ntToggle('showFocus', 'Focus timer on the start page', 'A simple countdown for working in focused bursts.'),
      row('Focus length', null, ntSelect('focusMinutes', [[15, '15 minutes'], [25, '25 minutes'], [45, '45 minutes'], [50, '50 minutes'], [90, '90 minutes']])),
      ntToggle('showTodos', 'To-do list on the start page', 'Saved on this PC only.'),
      ntToggle('showNotes', 'Quick notes on the start page', 'A scratchpad that saves as you type.')),

    h('h2', {}, 'Search'),
    h('div', { class: 'card' }, row('Search engine', 'Used when you type something that isn’t an address.', select('searchEngine', st.engines.map(e => [e.id, e.name])))),

    h('h2', {}, 'Browsing'),
    h('div', { class: 'card' },
      toggle('mouseNavButtons', 'Mouse back and forward buttons', 'The side buttons on your mouse go back and forward.'),
      toggle('blockPopups', 'Block pop-up windows', 'Pop-ups that open without you clicking are blocked. Applies to new tabs.'),
      row('Default page zoom', 'Applies to tabs you open from now on.', select('defaultZoom', [[75, '75%'], [90, '90%'], [100, '100%'], [110, '110%'], [125, '125%'], [150, '150%'], [175, '175%'], [200, '200%']])),
      toggle('developerTools', 'Developer tools', 'Adds Inspect Element to the right-click menu. Applies to tabs you open from now on.'),
      toggle('restoreSession', 'Reopen tabs on launch', 'Tabs load only when you select them, so startup stays light.'),
      toggle('keepSessionCookies', 'Keep me signed in across restarts', 'Saves login cookies that would otherwise be dropped on quit. Stored only on this PC.'),
      row('Unload idle tabs', 'Frees memory from background tabs. They reload when selected; unsaved form text is lost. Tabs playing audio and private tabs are never unloaded.',
        select('discardIdleTabsMinutes', [[0, 'Never'], [15, 'After 15 min'], [30, 'After 30 min'], [60, 'After 1 hour']]))),

    h('h2', {}, 'Downloads'),
    h('div', { class: 'card' },
      row('Download folder', null, h('div', { class: 'actions', style: 'margin:0' }, folderLabel,
        h('button', { onclick: async () => { folderLabel.textContent = (await call('downloads.chooseFolder')) || 'Downloads'; } }, 'Choose…'))),
      toggle('askDownloadLocation', 'Ask where to save each file', null),
      toggle('openDownloadsOnStart', 'Show the downloads panel when a download starts', null)),

    h('h2', {}, 'Privacy'),
    h('div', { class: 'card' },
      row('Lockdown mode', 'Turns on every protection at once. Some sites and video calls may stop working. Panic key: Ctrl+Alt+H mutes everything and hides Veil.',
        h('button', { onclick: lockdown }, 'Turn on')),
      toggle('adBlocking', 'Block ads and trackers', 'Uses the filter lists below. Turn off per site with the shield button.'),
      row('Cookies', 'Third-party blocking stops trackers while sites keep their own logins. “Block all” is strictest: only the sites listed below can keep cookies.',
        select('cookieMode', [['off', 'Allow all'], ['third-party', 'Block third-party (default)'], ['all', 'Block all except my sites']])),
      toggle('httpsUpgrade', 'Upgrade to HTTPS', 'Tries https:// first and asks before falling back to http.'),
      toggle('fingerprintProtection', 'Fingerprinting protection', 'Adds noise to canvas readback. Can break a few drawing or photo sites.'),
      toggle('sendGPC', 'Send Global Privacy Control', 'Tells sites you don’t want your data sold or shared.'),
      toggle('stripTracking', 'Remove tracking from links', 'Strips things like utm_ and fbclid from addresses before the page loads.'),
      toggle('opsecWebRTC', 'Block WebRTC IP leaks', 'Stops sites from finding your real IP address behind a VPN. Breaks web video calls.'),
      toggle('opsecBeacons', 'Block tracking pings and beacons', null),
      toggle('opsecReferrer', 'Hide where I came from', 'Websites you click through to won’t learn which page you were on. A few sites may complain.'),
      toggle('opsecHardware', 'Hide hardware details', 'Reports generic processor, memory and battery info to websites.'),
      toggle('denyMedia', 'Never allow camera or microphone', null),
      toggle('hideFromCapture', 'Hide Veil from screenshots and screen recording', 'The window shows up blank in captures and screen sharing.'),
      toggle('clearHistoryOnQuit', 'Clear history when quitting', 'Never touches cookies, so you stay signed in.')),
    h('h2', {}, 'Sites that may keep cookies (used by “Block all”)'),
    excBox,
    h('div', { class: 'actions' }, h('button', { onclick: () => set('cookieExceptions', $('#exc').value.split(/\n+/).map(x => x.trim().toLowerCase()).filter(Boolean)) }, 'Save sites')),

    h('h2', {}, 'Filter lists'),
    h('div', { class: 'card' }, ...st.sources.map(src => row(src.name,
      src.blurb + (src.url ? (src.updated ? ' Updated ' + fmt(src.updated) + '.' : ' Not downloaded yet.') : ''),
      sw(src.enabled, v => { src.enabled = v; const m = {}; st.sources.forEach(x => m[x.id] = x.enabled); set('enabledLists', m); })))),
    h('div', { class: 'actions' },
      h('button', { onclick: async () => {
        status.textContent = 'Downloading…';
        const r = await call('lists.update');
        status.textContent = r.failed.length ? 'Could not download: ' + r.failed.join(', ') : 'Lists updated.';
      } }, 'Download and update lists'),
      status),
    h('p', { class: 'hint' }, 'Downloading lists contacts easylist.to and ublockorigin.github.io directly, without cookies. It is the only time Veil talks to a third party. ',
      st.meta.networkRules + ' network rules and ' + st.meta.cosmeticRules + ' hiding rules are active; ' + st.meta.skippedRules + ' unsupported rules were skipped.'),
    h('div', { class: 'card', style: 'margin-top:14px' }, toggle('autoUpdateLists', 'Update lists automatically', 'Checks once a week when Veil starts.')),
    h('h2', {}, 'Custom filters'),
    h('textarea', { id: 'custom', spellcheck: false, placeholder: '||example.com^\nexample.org##.banner', value: s.customRules }),
    h('div', { class: 'actions' }, h('button', { onclick: () => set('customRules', $('#custom').value) }, 'Save filters')));

  // Search box: hides settings that don't match what you type.
  const main = root.querySelector('main');
  const finder = h('input', { type: 'text', placeholder: 'Search settings…', style: 'width:100%;margin:0 0 6px', oninput: e => {
    const t = e.target.value.trim().toLowerCase();
    main.querySelectorAll('.row').forEach(r => { r.style.display = !t || r.textContent.toLowerCase().includes(t) ? '' : 'none'; });
    main.querySelectorAll('.card').forEach(c => {
      const rows = c.querySelectorAll('.row');
      c.style.display = !t || rows.length === 0 || Array.from(rows).some(r => r.style.display !== 'none') ? '' : 'none';
    });
    main.querySelectorAll('h2').forEach(hh => {
      const c = hh.nextElementSibling;
      hh.style.display = !t || !c || !c.classList.contains('card') || c.style.display !== 'none' ? '' : 'none';
    });
  } });
  main.querySelector('h1').after(finder);
}

async function privacyPage() {
  const o = await call('privacy.overview');
  const cookies = await call('cookies.list');
  const perms = await call('permissions.list');
  const body = h('div');
  const draw = async () => {
    const allow = await call('allowlist.list');
    const list = h('div', { class: 'card' }, allow.length ? allow.map(host => h('div', { class: 'item' }, h('div', { class: 't' }, host),
      h('button', { onclick: async () => { await call('allowlist.remove', { host }); draw(); } }, 'Resume blocking'))) : empty('Blocking is on everywhere.'));
    const input = h('input', { type: 'text', placeholder: 'example.com' });
    body.replaceChildren(h('h2', {}, 'Blocking is off on these sites'), list,
      h('div', { class: 'actions' }, input, h('button', { onclick: async () => { if (input.value.trim()) { await call('allowlist.add', { host: input.value.trim() }); draw(); } } }, 'Turn off for site')));
  };
  const cookieCard = h('div', { class: 'card' });
  const q = h('input', { type: 'text', placeholder: 'Filter cookies by site', oninput: () => drawCookies() });
  const drawCookies = () => {
    const f = q.value.toLowerCase();
    const rows = cookies.filter(c => c.domain.includes(f)).slice(0, 200);
    cookieCard.replaceChildren(...(rows.length ? rows.map(c => h('div', { class: 'item' }, h('div', { class: 't' }, c.domain), h('span', { class: 'mute' }, c.count),
      h('button', { onclick: async () => { await call('cookies.clearDomain', { domain: c.domain }); c.count = 0; cookies.splice(cookies.indexOf(c), 1); drawCookies(); } }, 'Remove'))) : [empty('No cookies.')]));
  };
  drawCookies();
  shell('Privacy',
    h('div', { class: 'stats' },
      ...[[o.rules, 'rules blocking'], [o.cookieDomains, 'sites with cookies'], [o.history, 'history entries'], [o.bookmarks, 'bookmarks']]
        .map(([n, l]) => h('div', { class: 'stat' }, h('b', {}, n.toLocaleString()), h('span', {}, l)))),
    h('p', { class: 'hint' }, 'Veil has no telemetry, no account and no sync. History, bookmarks, cookies and settings stay in %APPDATA%\\Veil and the WebView2 data folder on this PC. Veil never deletes cookies on its own.'),
    body,
    h('h2', {}, 'Site permissions'),
    h('div', { class: 'card' }, perms.length ? perms.map(p => h('div', { class: 'item' }, h('div', { class: 't' }, p.host + ' · ' + p.kind), h('span', { class: 'mute' }, p.allowed ? 'Allowed' : 'Blocked'),
      h('button', { onclick: async (e) => { await call('permissions.remove', { host: p.host, kind: p.kind }); e.target.closest('.item').remove(); } }, 'Reset'))) : empty('No saved permissions.')),
    h('h2', {}, 'Cookies'), q, h('div', { style: 'height:10px' }), cookieCard,
    h('div', { class: 'actions' },
      h('button', { class: 'danger', onclick: async () => { if (confirm('Remove all cookies? You will be signed out of every site.')) { await call('cookies.clearAll'); location.reload(); } } }, 'Remove all cookies'),
      h('button', { class: 'danger', onclick: async () => { if (confirm('Remove all cookies, local storage, and cached site data? You will be signed out everywhere.')) { await call('siteData.clearAll'); location.reload(); } } }, 'Remove all site data')));
  draw();
}

async function historyPage() {
  const list = h('div', { class: 'card' });
  const q = h('input', { type: 'text', placeholder: 'Search history', oninput: () => draw() });
  const draw = async () => {
    const items = await call('history.list', { q: q.value });
    list.replaceChildren(...(items.length ? items.map(i => h('div', { class: 'item' },
      h('div', { class: 't' }, h('div', {}, h('a', { href: i.url }, i.title || i.url)), h('div', { class: 'mute url' }, i.url)),
      h('span', { class: 'mute' }, fmt(i.date)),
      h('button', { onclick: async () => { await call('history.remove', { id: i.id }); draw(); } }, 'Remove'))) : [empty('Nothing here.')]));
  };
  shell('History', q, h('div', { style: 'height:12px' }), list,
    h('div', { class: 'actions' }, h('button', { class: 'danger', onclick: async () => { if (confirm('Clear all history?')) { await call('history.clear'); draw(); } } }, 'Clear history')));
  draw();
}

async function bookmarksPage() {
  const list = h('div', { class: 'card' });
  const draw = async () => {
    const items = await call('bookmarks.list');
    list.replaceChildren(...(items.length ? items.map(i => h('div', { class: 'item' },
      h('div', { class: 't' }, h('div', {}, h('a', { href: i.url }, i.title)), h('div', { class: 'mute url' }, i.url)),
      h('button', { onclick: async () => { await call('bookmarks.remove', { url: i.url }); draw(); } }, 'Remove'))) : [empty('Press Ctrl+D on any page to bookmark it.')]));
  };
  shell('Bookmarks', list); draw();
}

async function downloadsPage() {
  const list = h('div', { class: 'card' });
  const draw = async () => {
    const items = await call('downloads.list');
    list.replaceChildren(...(items.length ? items.map(i => h('div', { class: 'item' },
      h('div', { class: 't' }, h('div', {}, i.name), h('div', { class: 'mute url' }, i.source),
        i.state === 'running' ? h('div', { class: 'bar' }, h('i', { style: 'width:' + Math.round((i.progress || 0) * 100) + '%' })) : null),
      h('span', { class: 'mute' }, i.state === 'done' ? 'Done' : i.state === 'failed' ? 'Failed' : Math.round((i.progress || 0) * 100) + '%'),
      i.state === 'done' ? h('button', { onclick: () => call('downloads.open', { id: i.id }) }, 'Open') : null,
      i.state !== 'running' && i.state !== 'failed' ? h('button', { onclick: () => call('downloads.reveal', { id: i.id }) }, 'Show in folder') : null)) : [empty('No downloads yet.')]));
    return items.some(i => i.state === 'running');
  };
  shell('Downloads', list,
    h('div', { class: 'actions' }, h('button', { onclick: async () => { await call('downloads.clear'); draw(); } }, 'Clear finished')));
  draw();
  setInterval(() => { if (!document.hidden) draw(); }, 1500);
}

const LINES = ['Quiet web, loud ideas.', 'Nobody is watching. Browse freely.', 'Small tabs, big thoughts.', 'Today is a good day to close twelve tabs.',
  'Take the scenic route through the internet.', 'Hydrate. Then keep scrolling.', 'Curiosity is the best extension.', 'Fresh tab, fresh start.',
  'Be kind to your RAM.', 'Somewhere, a cat video is waiting for you.', 'Make it a good one.', 'The best tab is the one you meant to open.'];

function backdrop(bg, animated, nt) {
  if (!bg || bg === 'glow') bg = 'aurora';
  document.body.dataset.bg = bg === 'custom' ? 'midnight' : bg;
  const layers = [];
  if (bg === 'plain' || bg === 'grain') {
    layers.push(h('div', { class: 'flat' }));
  } else if (bg === 'poster') {
    layers.push(h('div', { class: 'poster' }, h('i', { class: 'p1' }), h('i', { class: 'p2' }), h('i', { class: 'p3' }), h('i', { class: 'p4' })));
  } else if (bg === 'custom') {
    layers.push(h('div', { class: 'bgimg', id: 'bgimg' }));
    call('background.get').then(d => { if (d) $('#bgimg').style.backgroundImage = 'url(' + d + ')'; }).catch(() => {});
  } else {
    layers.push(h('div', { class: 'bg' + (animated ? ' anim' : '') }, h('div', { class: 'blob a' }), h('div', { class: 'blob b' }), h('div', { class: 'blob c' })));
  }
  if (nt && nt.dim) layers.push(h('div', { class: 'dim', style: 'opacity:' + (nt.dim / 100) }));
  document.body.prepend(...layers);
}
const magnifier = () => { const s = h('span'); s.innerHTML = '<svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg>'; return s; };
const searchForm = placeholder => {
  const q = h('input', { type: 'text', placeholder, spellcheck: false });
  return h('form', { class: 'sbox', onsubmit: e => { e.preventDefault(); const v = q.value.trim(); if (v) call('navigate', { text: v }); } }, magnifier(), q);
};

function privateTab(nt) {
  document.title = 'Private Tab';
  backdrop('private', nt.animated, null);
  put(root, h('div', { class: 'nt' },
    h('div', { class: 'hello' }, 'Veil'),
    h('div', { class: 'ptitle' }, 'Private tab'),
    h('p', { class: 'priv' }, 'Veil won’t keep history, cookies or site data from private tabs, and wipes them when you close the last one. Ad and tracker blocking stays on.'),
    h('p', { class: 'priv', style: 'margin-top:0' }, 'Websites, your network and your downloads can still see what you do.'),
    searchForm('Search privately or enter address')));
}

async function newtabPage() {
  const st = await call('settings.get');
  const nt = st.settings.newTab;
  document.title = 'New Tab';
  if (location.search.indexOf('private') >= 0) return privateTab(nt);
  document.body.classList.add('f-' + (nt.font || 'modern'));
  backdrop(nt.background, nt.animated, nt);
  const icons = await call('newtab.icons').catch(() => ({}));
  let editing = false;
  const save = () => call('settings.set', { key: 'newTab', value: nt });
  const hue = str => { let x = 7; for (const c of str.toLowerCase()) x = (x * 31 + c.charCodeAt(0)) % 360; return x; };
  const hello = h('div', { class: 'hello' }), clock = h('div', { class: 'clock' }), date = h('div', { class: 'date' });
  const greet = d => {
    const hr = d.getHours();
    const part = hr < 5 ? 'Still up' : hr < 12 ? 'Good morning' : hr < 18 ? 'Good afternoon' : 'Good evening';
    return nt.greeting || (part + (nt.name ? ', ' + nt.name : ''));
  };
  const tick = () => {
    if (document.hidden) return;
    const d = new Date();
    hello.textContent = greet(d);
    clock.textContent = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: !nt.use24Hour });
    date.textContent = d.toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric' });
  };
  const uid = () => Math.random().toString(36).slice(2, 10);
  const fmtLeft = ms => { const s = Math.max(0, Math.ceil(ms / 1000)); return String(Math.floor(s / 60)).padStart(2, '0') + ':' + String(s % 60).padStart(2, '0'); };
  let focusUpdate = null;
  setInterval(() => { if (focusUpdate && !document.hidden) focusUpdate(); }, 1000);
  const focusBox = () => {
    const time = h('div', { class: 'ftime' });
    const btn = h('button', { class: 'fbtn' });
    const update = () => {
      const left = nt.focusEnd - Date.now();
      if (nt.focusEnd && left > 0) { time.textContent = fmtLeft(left); btn.textContent = 'Stop'; }
      else if (nt.focusEnd) { time.textContent = 'Done!'; btn.textContent = 'Again'; }
      else { time.textContent = String(nt.focusMinutes || 25).padStart(2, '0') + ':00'; btn.textContent = 'Start'; }
    };
    btn.addEventListener('click', () => {
      const running = nt.focusEnd && nt.focusEnd - Date.now() > 0;
      nt.focusEnd = running ? 0 : Date.now() + (nt.focusMinutes || 25) * 60000;
      save(); update();
    });
    focusUpdate = update; update();
    return h('div', { class: 'pcard focus' }, h('div', { class: 'ptitle' }, 'Focus'), time, btn);
  };
  const todoBox = () => {
    const list = h('div', { class: 'tlist' });
    const input = h('input', { type: 'text', placeholder: 'Add a task, press Enter' });
    const clear = h('b', { class: 'tclear' }, 'clear done');
    const render = () => {
      list.textContent = '';
      nt.todos.forEach((t, i) => {
        const box = h('input', { type: 'checkbox', checked: !!t.done });
        box.addEventListener('change', () => { t.done = box.checked; save(); render(); });
        const del = h('b', { class: 'tdel' }, '×');
        del.addEventListener('click', () => { nt.todos.splice(i, 1); save(); render(); });
        list.append(h('div', { class: 'titem' + (t.done ? ' done' : '') }, box, h('span', {}, t.text), del));
      });
    };
    clear.addEventListener('click', () => { nt.todos = nt.todos.filter(t => !t.done); save(); render(); });
    input.addEventListener('keydown', e => {
      if (e.key === 'Enter' && input.value.trim()) { nt.todos.push({ id: uid(), text: input.value.trim(), done: false }); input.value = ''; save(); render(); }
    });
    render();
    return h('div', { class: 'pcard todos' }, h('div', { class: 'ptitle' }, 'To-do', clear), list, input);
  };
  const notesBox = () => {
    const ta = h('textarea', { placeholder: 'Quick notes…', spellcheck: false, value: nt.notes || '' });
    let timer = null;
    ta.addEventListener('input', () => { nt.notes = ta.value; clearTimeout(timer); timer = setTimeout(save, 400); });
    return h('div', { class: 'pcard notes' }, h('div', { class: 'ptitle' }, 'Notes'), ta);
  };
  const productivity = () => (nt.showFocus || nt.showTodos || nt.showNotes)
    ? h('div', { class: 'prod' }, nt.showFocus ? focusBox() : null, nt.showTodos ? todoBox() : null, nt.showNotes ? notesBox() : null)
    : null;
  const form = searchForm('Search or enter address');
  const wrap = h('div', { class: 'nt cs-' + nt.clockSize + ' ts-' + nt.tileStyle + ' tz-' + nt.tileSize + (nt.showLabels ? '' : ' nolabels') });
  const draw = () => {
    const tiles = nt.shortcuts.map((s, i) => h('a', { class: 'tile', href: editing ? '#' : s.url, onclick: e => { if (editing) e.preventDefault(); } },
      icons[s.url]
        ? h('div', { class: 'm icon' }, h('img', { src: icons[s.url] }))
        : h('div', { class: 'm', style: 'background:linear-gradient(145deg,hsl(' + hue(s.title) + ',38%,46%),hsl(' + hue(s.title) + ',34%,28%))' }, (s.title[0] || '•').toUpperCase()),
      h('div', { class: 'n' }, s.title),
      editing ? h('span', { class: 'x', onclick: e => { e.preventDefault(); e.stopPropagation(); nt.shortcuts.splice(i, 1); save(); draw(); } }, '×') : null));
    const t = h('input', { type: 'text', placeholder: 'Name' }), u = h('input', { type: 'text', placeholder: 'example.com' });
    put(wrap,
      nt.showClock ? hello : null, nt.showClock ? clock : null, nt.showClock ? date : null,
      nt.showSearch ? form : null,
      h('div', { class: 'tiles' }, tiles),
      editing ? null : productivity(),
      editing ? h('div', { class: 'edit' }, t, u, h('button', { onclick: () => {
        if (!t.value.trim() || !u.value.trim()) return;
        let url = u.value.trim(); if (!/^[a-z]+:\/\//i.test(url)) url = 'https://' + url;
        nt.shortcuts.push({ title: t.value.trim(), url }); save(); draw();
      } }, 'Add')) : null,
      h('button', { class: 'link', onclick: () => { editing = !editing; draw(); } }, editing ? 'Done' : 'Edit shortcuts'),
      nt.funLines ? h('div', { class: 'fun' }, LINES[Math.floor(Date.now() / 86400000) % LINES.length]) : null);
    tick();
  };
  put(root, wrap); draw();
  setInterval(tick, 20000);
  document.addEventListener('visibilitychange', async () => {
    if (document.hidden || editing) return;
    const tag = (document.activeElement && document.activeElement.tagName) || '';
    if (/INPUT|TEXTAREA/.test(tag)) return;
    try {
      const fresh = (await call('settings.get')).settings.newTab;
      nt.todos = fresh.todos; nt.notes = fresh.notes; nt.focusEnd = fresh.focusEnd;
      draw();
    } catch (e) {}
  });
  // Keyboard: press 1-9 to open a shortcut, / to jump to the search box.
  document.addEventListener('keydown', e => {
    if (editing || e.metaKey || e.ctrlKey || e.altKey) return;
    const tag = (document.activeElement && document.activeElement.tagName) || '';
    if (/INPUT|TEXTAREA/.test(tag)) return;
    if (e.key === '/') { e.preventDefault(); const i = $('.sbox input'); if (i) i.focus(); return; }
    const n = parseInt(e.key, 10);
    if (n >= 1 && n <= nt.shortcuts.length) location.href = nt.shortcuts[n - 1].url;
  });
}

call('settings.get').then(st => applyAccent(st.settings.accent)).catch(() => {});
({ settings: settingsPage, privacy: privacyPage, history: historyPage, bookmarks: bookmarksPage, downloads: downloadsPage, newtab: newtabPage }[page] || (() => {}))();