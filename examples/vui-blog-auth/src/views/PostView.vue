<script setup>
import { ref, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { api } from '../lib/api.js';

const route = useRoute();
const router = useRouter();
const post = ref(null);
const error = ref(null);
const loading = ref(true);

const fmt = (t) => new Date(t).toLocaleString();

onMounted(async () => {
  try {
    post.value = await api('GET', `/api/posts/${route.params.id}`);
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <div class="view active">
    <button class="post-single__back" @click="router.push('/')">← cd ..</button>

    <p v-if="loading" class="post-card__meta">loading…</p>

    <div v-else-if="error" class="empty">
      <div class="empty__icon">⚠</div>
      <h3>not found</h3>
      <p>{{ error }}</p>
    </div>

    <template v-else>
      <h1 class="post-single__title">{{ post.title }}</h1>
      <div class="post-single__meta">{{ fmt(post.createdAt) }}</div>
      <div class="post-single__body">{{ post.content }}</div>
    </template>
  </div>
</template>
