<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { adminToken, api } from '../lib/api.js';

const route = useRoute();
const router = useRouter();
const id = computed(() => (route.name === 'admin-edit' ? route.params.id : null));

const title = ref('');
const slug = ref('');
const content = ref('');
const published = ref(false);
const slugTouched = ref(false);
const error = ref(null);
const saving = ref(false);

// Auto-generate the slug from the title until the user edits it by hand.
watch(title, (v) => {
  if (!slugTouched.value) {
    slug.value = v
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '');
  }
});

onMounted(async () => {
  if (!adminToken.value) {
    router.push('/admin');
    return;
  }
  if (id.value) {
    try {
      const posts = await api('GET', '/api/admin/posts');
      const p = posts.find((x) => x.id === id.value);
      if (p) {
        title.value = p.title;
        slug.value = p.slug;
        content.value = p.content;
        published.value = p.published;
        slugTouched.value = true;
      }
    } catch (e) {
      error.value = e.message;
    }
  }
});

async function save() {
  if (!title.value.trim() || !content.value.trim()) {
    error.value = 'title and content required';
    return;
  }
  saving.value = true;
  error.value = null;
  const body = {
    title: title.value,
    slug: slug.value,
    content: content.value,
    published: published.value
  };
  try {
    if (id.value) await api('PUT', `/api/admin/posts/${id.value}`, body);
    else await api('POST', '/api/admin/posts', body);
    router.push('/admin');
  } catch (e) {
    error.value = e.message;
    saving.value = false;
  }
}
</script>

<template>
  <div class="view active">
    <div class="form-panel">
      <div class="form-panel__header">
        <h1 class="page-title" style="margin: 0">{{ id ? 'edit post' : 'new post' }}</h1>
        <router-link class="btn btn-ghost" to="/admin">← cancel</router-link>
      </div>

      <form @submit.prevent="save">
        <div class="form-row">
          <div class="form-group">
            <label class="form-label" for="title">title</label>
            <input id="title" class="form-input" v-model="title" />
          </div>
          <div class="form-group">
            <label class="form-label" for="slug">slug</label>
            <input id="slug" class="form-input" v-model="slug" @input="slugTouched = true" />
          </div>
        </div>

        <div class="form-group">
          <label class="form-label" for="content">content</label>
          <textarea id="content" class="form-textarea" v-model="content"></textarea>
        </div>

        <label class="form-check">
          <input type="checkbox" v-model="published" />
          <span>published</span>
        </label>

        <p v-if="error" class="post-card__meta" style="color: var(--red); margin-top: 12px">{{ error }}</p>

        <div class="row-actions" style="margin-top: 20px">
          <button class="btn btn-primary" type="submit" :disabled="saving">
            {{ saving ? 'saving…' : 'save' }}
          </button>
          <router-link class="btn btn-ghost" to="/admin">cancel</router-link>
        </div>
      </form>
    </div>
  </div>
</template>
