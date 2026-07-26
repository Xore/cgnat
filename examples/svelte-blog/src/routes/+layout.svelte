<script>
  import '../app.css';
  import { page } from '$app/stores';
  import { adminToken } from '$lib/api';

  const ticker = [
    'SVELTE 5', 'RUNES', '$STATE()', '$DERIVED()', '$EFFECT()',
    'NO VDOM', 'SELF-HOSTED', 'CGNAT', 'HEINSBERG, DE', 'ZERO CLOUD'
  ];

  $: isAdmin = $page.url.pathname.startsWith('/admin');
</script>

<div class="scene" aria-hidden="true">
  <div class="scene__glow scene__glow--warm"></div>
  <div class="scene__glow scene__glow--cool"></div>
  <div class="scene__grid"></div>
  <div class="scene__vignette"></div>
</div>

<header class="site-header">
  <div class="meta">
    <div class="container meta__inner">
      <span class="status"><span class="status__led"></span> SVELTE BLOG ONLINE</span>
    </div>
  </div>
  <div class="container nav">
    <a class="brand" href="/" aria-label="xore svelte blog home">
      <svg class="brand__mark" viewBox="0 0 32 32" width="24" height="24" aria-hidden="true">
        <path d="M6 6l20 20M26 6L6 26" stroke="url(#bg)" stroke-width="3.4" stroke-linecap="round" />
        <defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stop-color="#38bdf8" /><stop offset="1" stop-color="#34d399" />
        </linearGradient></defs>
      </svg>
      <span class="brand__text">XORE<span class="brand__slash">//</span>SVELTE</span>
    </a>
    <div class="nav__right">
      {#if $adminToken}<span class="admin-badge">ADMIN</span>{/if}
      <a class="nav-btn" class:active={!isAdmin} href="/">POSTS</a>
      <a class="nav-btn" class:active={isAdmin} href="/admin">ADMIN</a>
    </div>
  </div>
</header>

<div class="marquee" aria-hidden="true">
  <div class="marquee__track">
    {#each [...ticker, ...ticker] as item}
      <span class="marquee__item">{item}</span>
      <span class="marquee__dia">◆</span>
    {/each}
  </div>
</div>

<main class="main">
  <div class="container">
    <slot />
  </div>
</main>

<footer class="footer">
  <div class="container footer__inner">
    <span>xore//svelte</span>
    <span class="footer__sep">◆</span>
    <span>svelte 5 runes</span>
    <span class="footer__sep">◆</span>
    <span>self-hosted</span>
    <span class="footer__sep">◆</span>
    <span>cgnat tunnel</span>
  </div>
</footer>
