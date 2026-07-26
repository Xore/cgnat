<script setup>
import { ref, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { api } from '../lib/api.js';

const router = useRouter();
const posts = ref([]);
const loading = ref(true);
const error = ref(null);

const fmt = (t) =>
  new Date(t).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });

const open = (id) => router.push(`/post/${id}`);

onMounted(async () => {
  try {
    posts.value = await api('GET', '/api/posts');
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <div class="view active">
    <h1 class="page-title">posts</h1>

    <p v-if="loading" class="post-card__meta">loading posts…</p>

    <div v-else-if="error" class="empty">
      <div class="empty__icon">⚠</div>
      <h3>failed to load</h3>
      <p>{{ error }}</p>
    </div>

    <div v-else-if="posts.length === 0" class="empty">
      <div class="empty__icon">∅</div>
      <h3>no posts yet</h3>
      <p>published posts will appear here</p>
    </div>

    <div v-else class="post-grid">
      <article
        v-for="p in posts"
        :key="p.id"
        class="post-card"
        role="button"
        tabindex="0"
        @click="open(p.id)"
        @keydown.enter="open(p.id)"
      >
        <h2 class="post-card__title">{{ p.title }}</h2>
        <div class="post-card__meta">{{ fmt(p.createdAt) }}</div>
        <p class="post-card__excerpt">{{ p.content }}</p>
        <div class="post-card__arrow">read <span>→</span></div>
      </article>
    </div>
  </div>
</template>
