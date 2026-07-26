<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { adminToken } from './lib/api.js';

const route = useRoute();
const isAdmin = computed(() => route.path.startsWith('/admin'));

const ticker = [
  'SELF-HOSTED', 'NO CLOUD', 'HARDWARE I OWN', 'HEINSBERG, DE',
  'ZERO-TRUST', 'NO OPEN PORTS', 'CGNAT GATEWAY', 'JUST CONFIGS & PACKETS'
];
const tickerLoop = [...ticker, ...ticker];
</script>

<template>
  <div class="scene" aria-hidden="true">
    <div class="scene__glow scene__glow--warm"></div>
    <div class="scene__glow scene__glow--cool"></div>
    <div class="scene__grid"></div>
    <div class="scene__vignette"></div>
  </div>

  <header class="site-header">
    <div class="meta">
      <div class="container meta__inner">
        <span class="status"><span class="status__led"></span> BLOG ONLINE</span>
      </div>
    </div>
    <div class="container nav">
      <router-link class="brand" to="/" aria-label="xore blog home">
        <svg class="brand__mark" viewBox="0 0 32 32" width="24" height="24" aria-hidden="true">
          <path d="M6 6l20 20M26 6L6 26" stroke="url(#bg)" stroke-width="3.4" stroke-linecap="round" />
          <defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stop-color="#38bdf8" /><stop offset="1" stop-color="#34d399" />
          </linearGradient></defs>
        </svg>
        <span class="brand__text">XORE<span class="brand__slash">//</span>BLOG</span>
      </router-link>
      <div class="nav__right">
        <span v-if="adminToken" class="admin-badge">ADMIN</span>
        <router-link class="nav-btn" :class="{ active: !isAdmin }" to="/">POSTS</router-link>
        <router-link class="nav-btn" :class="{ active: isAdmin }" to="/admin">ADMIN</router-link>
      </div>
    </div>
  </header>

  <div class="marquee" aria-hidden="true">
    <div class="marquee__track">
      <template v-for="(item, i) in tickerLoop" :key="i">
        <span class="marquee__item">{{ item }}</span>
        <span class="marquee__dia">◆</span>
      </template>
    </div>
  </div>

  <main class="main">
    <div class="container">
      <router-view />
    </div>
  </main>

  <footer class="footer">
    <div class="container footer__inner">
      <span>xore//blog</span>
      <span class="footer__sep">◆</span>
      <span>self-hosted</span>
      <span class="footer__sep">◆</span>
      <span>no cloud</span>
    </div>
  </footer>
</template>
