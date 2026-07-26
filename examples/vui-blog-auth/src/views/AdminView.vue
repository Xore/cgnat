<script setup>
import { ref, onMounted } from 'vue';
import { adminToken, api } from '../lib/api.js';

const password = ref('');
const posts = ref([]);
const error = ref(null);
const loading = ref(false);

const fmt = (t) => new Date(t).toLocaleDateString();

async function login() {
  if (!password.value.trim()) {
    error.value = 'enter password';
    return;
  }
  error.value = null;
  try {
    const { token } = await api('POST', '/api/admin/login', { password: password.value });
    adminToken.value = token;
    await loadPosts();
  } catch (e) {
    error.value = e.message;
  }
}

async function loadPosts() {
  loading.value = true;
  error.value = null;
  try {
    posts.value = await api('GET', '/api/admin/posts');
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
}

async function del(id) {
  if (!confirm('delete this post?')) return;
  try {
    await api('DELETE', `/api/admin/posts/${id}`);
    await loadPosts();
  } catch (e) {
    error.value = e.message;
  }
}

function logout() {
  adminToken.value = null;
  posts.value = [];
}

// Reload the table if we return here already authenticated (client nav).
onMounted(() => {
  if (adminToken.value) loadPosts();
});
</script>

<template>
  <div class="view active">
    <div v-if="!adminToken" class="admin-gate">
      <h2 class="admin-gate__title">// admin access</h2>
      <form @submit.prevent="login">
        <div class="form-group">
          <label class="form-label" for="pw">password</label>
          <input id="pw" class="form-input" type="password" v-model="password" autocomplete="current-password" />
        </div>
        <p v-if="error" class="post-card__meta" style="color: var(--red)">{{ error }}</p>
        <button class="btn btn-primary" type="submit" style="width: 100%">authenticate</button>
      </form>
    </div>

    <template v-else>
      <div class="admin-header">
        <h1 class="page-title" style="margin: 0">admin · posts</h1>
        <div class="row-actions">
          <router-link class="btn btn-primary" to="/admin/new">+ new post</router-link>
          <button class="btn btn-ghost" @click="logout">logout</button>
        </div>
      </div>

      <p v-if="loading" class="post-card__meta">loading…</p>

      <div v-else-if="error" class="empty">
        <div class="empty__icon">⚠</div>
        <h3>error</h3>
        <p>{{ error }}</p>
      </div>

      <div v-else-if="posts.length === 0" class="empty">
        <div class="empty__icon">∅</div>
        <h3>no posts</h3>
        <p>create your first post</p>
      </div>

      <div v-else class="post-table">
        <table>
          <thead>
            <tr>
              <th>title</th>
              <th>status</th>
              <th>created</th>
              <th>actions</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="p in posts" :key="p.id">
              <td>{{ p.title }}</td>
              <td>
                <span v-if="p.published" class="badge badge-green">published</span>
                <span v-else class="badge badge-muted">draft</span>
              </td>
              <td>{{ fmt(p.createdAt) }}</td>
              <td>
                <div class="row-actions">
                  <router-link class="btn btn-ghost" :to="`/admin/${p.id}`">edit</router-link>
                  <button class="btn btn-danger" @click="del(p.id)">del</button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>
