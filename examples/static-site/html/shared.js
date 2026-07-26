/* shared.js — injects sidebar + topbar into every docs page */
(function () {
  'use strict';

  /* ── current page highlighting ── */
  const path = location.pathname.replace(/\/+$/, '') || '/';

  const NAV = [
    { label: '🏠 Home', href: '/' },
    { label: '━━━━━━━━━━━━━━━', href: null },
    { label: '📖 Documentation', href: null, section: true },
    { label: '⚡ Quick Start',   href: '/docs/', indent: 1 },
    { label: '🔧 Setup Guide',   href: '/docs/setup.html', indent: 1 },
    { label: '📦 Examples',      href: '/docs/examples.html', indent: 1 },
    { label: '🚀 Performance',   href: '/docs/performance.html', indent: 1 },
    { label: '🩺 Troubleshooting', href: '/docs/troubleshooting.html', indent: 1 },
    { label: '━━━━━━━━━━━━━━━', href: null },
    { label: '🔗 GitHub', href: 'https://github.com/Xore/nan', external: true },
  ];

  /* ── sidebar HTML ── */
  const sidebarHTML = `
<nav id="sidebar">
  <div class="sidebar-logo">
    <a href="/">🛡️ CGNAT Gateway</a>
  </div>
  <ul class="nav-tree">
    ${NAV.map(n => {
      if (!n.href && !n.section) return `<li class="nav-divider">${n.label.includes('━') ? '' : n.label}</li>`;
      if (n.section) return `<li class="nav-section">${n.label}</li>`;
      const active = n.href && (path === n.href.replace(/\/+$/, '') || path + '/' === n.href);
      const indent = n.indent ? ' style="padding-left:24px"' : '';
      const target = n.external ? ' target="_blank" rel="noopener"' : '';
      return `<li${indent ? indent.replace('style', ' style') : ''}><a href="${n.href}"${target} class="${active ? 'active' : ''}">${n.label}</a></li>`;
    }).join('\n    ')}
  </ul>
  <div class="sidebar-footer">CGNAT Gateway Docs</div>
</nav>`;

  /* ── topbar HTML ── */
  const topbarHTML = `
<header id="topbar">
  <button id="menu-toggle" aria-label="menu">☰</button>
  <a class="topbar-title" href="/">🛡️ CGNAT Gateway</a>
  <span id="topbar-breadcrumb"></span>
</header>`;

  /* ── inject ── */
  document.body.insertAdjacentHTML('afterbegin', topbarHTML + sidebarHTML);

  /* ── mobile toggle ── */
  document.getElementById('menu-toggle').addEventListener('click', () => {
    document.getElementById('sidebar').classList.toggle('open');
  });

  /* ── breadcrumb ── */
  const active = NAV.find(n => n.href && (path === n.href.replace(/\/+$/, '') || path + '/' === n.href));
  if (active) document.getElementById('topbar-breadcrumb').textContent = active.label.replace(/^[^\s]+\s/, '');

  /* ── copy buttons ── */
  document.querySelectorAll('pre code').forEach(block => {
    const wrap = block.closest('pre');
    const btn = document.createElement('button');
    btn.className = 'copy-btn';
    btn.textContent = 'copy';
    btn.addEventListener('click', () => {
      navigator.clipboard.writeText(block.textContent).then(() => {
        btn.textContent = '✓ copied';
        btn.classList.add('copied');
        setTimeout(() => { btn.textContent = 'copy'; btn.classList.remove('copied'); }, 2000);
      });
    });
    wrap.style.position = 'relative';
    wrap.appendChild(btn);
  });

  /* ── anchor links ── */
  document.querySelectorAll('h2[id], h3[id]').forEach(h => {
    const a = document.createElement('a');
    a.className = 'anchor-link';
    a.href = '#' + h.id;
    a.textContent = '#';
    h.appendChild(a);
  });
})();
