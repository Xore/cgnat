<script lang="ts">
  import { onMount } from 'svelte';
  import { get } from 'svelte/store';
  import { adminToken, api } from '$lib/api';
  import type { Post } from '$lib/types';

  let password = $state('');
  let posts = $state<Post[]>([]);
  let error = $state<string | null>(null);
  let loading = $state(false);

  // in-view sub-state: list <-> form (create/edit)
  let mode = $state<'list' | 'form'>('list');
  let editingId = $state<string | null>(null);
  let fTitle = $state('');
  let fSlug = $state('');
  let fContent = $state('');
  let fPublished = $state(false);
  let slugTouched = $state(false);
  let saving = $state(false);

  const fmt = (t: number) => new Date(t).toLocaleDateString();

  async function login() {
    if (!password.trim()) {
      error = 'enter password';
      return;
    }
    error = null;
    try {
      const { token } = await api<{ token: string }>('POST', '/api/admin/login', { password });
      adminToken.set(token);
      await loadPosts();
    } catch (e) {
      error = (e as Error).message;
    }
  }

  async function loadPosts() {
    loading = true;
    error = null;
    try {
      posts = await api<Post[]>('GET', '/api/admin/posts');
    } catch (e) {
      error = (e as Error).message;
    } finally {
      loading = false;
    }
  }

  function newPost() {
    editingId = null;
    fTitle = '';
    fSlug = '';
    fContent = '';
    fPublished = false;
    slugTouched = false;
    error = null;
    mode = 'form';
  }

  function editPost(p: Post) {
    editingId = p.id;
    fTitle = p.title;
    fSlug = p.slug;
    fContent = p.content;
    fPublished = p.published;
    slugTouched = true;
    error = null;
    mode = 'form';
  }

  function autoSlug() {
    if (!slugTouched) {
      fSlug = fTitle
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '');
    }
  }

  async function save() {
    if (!fTitle.trim() || !fContent.trim()) {
      error = 'title and content required';
      return;
    }
    saving = true;
    error = null;
    // The server admin route keys PUT/DELETE off body.id (see api/admin/posts).
    const body = {
      id: editingId ?? undefined,
      title: fTitle,
      slug: fSlug,
      content: fContent,
      published: fPublished
    };
    try {
      if (editingId) await api('PUT', '/api/admin/posts', body);
      else await api('POST', '/api/admin/posts', body);
      mode = 'list';
      await loadPosts();
    } catch (e) {
      error = (e as Error).message;
    } finally {
      saving = false;
    }
  }

  async function del(id: string) {
    if (!confirm('delete this post?')) return;
    try {
      await api('DELETE', '/api/admin/posts', { id });
      await loadPosts();
    } catch (e) {
      error = (e as Error).message;
    }
  }

  function logout() {
    adminToken.set(null);
    posts = [];
    mode = 'list';
  }

  // Reload the table if we arrive already authenticated (client nav).
  onMount(() => {
    if (get(adminToken)) loadPosts();
  });
</script>

<div class="view active">
  {#if !$adminToken}
    <div class="admin-gate">
      <h2 class="admin-gate__title">// admin access</h2>
      <form onsubmit={(e) => { e.preventDefault(); login(); }}>
        <div class="form-group">
          <label class="form-label" for="pw">password</label>
          <input id="pw" class="form-input" type="password" bind:value={password} autocomplete="current-password" />
        </div>
        {#if error}<p class="post-card__meta" style="color: var(--red)">{error}</p>{/if}
        <button class="btn btn-primary" type="submit" style="width: 100%">authenticate</button>
      </form>
    </div>
  {:else if mode === 'form'}
    <div class="form-panel">
      <div class="form-panel__header">
        <h1 class="page-title" style="margin: 0">{editingId ? 'edit post' : 'new post'}</h1>
        <button class="btn btn-ghost" type="button" onclick={() => (mode = 'list')}>← cancel</button>
      </div>
      <form onsubmit={(e) => { e.preventDefault(); save(); }}>
        <div class="form-row">
          <div class="form-group">
            <label class="form-label" for="ft">title</label>
            <input id="ft" class="form-input" bind:value={fTitle} oninput={autoSlug} />
          </div>
          <div class="form-group">
            <label class="form-label" for="fs">slug</label>
            <input id="fs" class="form-input" bind:value={fSlug} oninput={() => (slugTouched = true)} />
          </div>
        </div>
        <div class="form-group">
          <label class="form-label" for="fc">content</label>
          <textarea id="fc" class="form-textarea" bind:value={fContent}></textarea>
        </div>
        <label class="form-check">
          <input type="checkbox" bind:checked={fPublished} />
          <span>published</span>
        </label>
        {#if error}<p class="post-card__meta" style="color: var(--red); margin-top: 12px">{error}</p>{/if}
        <div class="row-actions" style="margin-top: 20px">
          <button class="btn btn-primary" type="submit" disabled={saving}>{saving ? 'saving…' : 'save'}</button>
          <button class="btn btn-ghost" type="button" onclick={() => (mode = 'list')}>cancel</button>
        </div>
      </form>
    </div>
  {:else}
    <div class="admin-header">
      <h1 class="page-title" style="margin: 0">admin · posts</h1>
      <div class="row-actions">
        <button class="btn btn-primary" onclick={newPost}>+ new post</button>
        <button class="btn btn-ghost" onclick={logout}>logout</button>
      </div>
    </div>

    {#if loading}
      <p class="post-card__meta">loading…</p>
    {:else if error}
      <div class="empty">
        <div class="empty__icon">⚠</div>
        <h3>error</h3>
        <p>{error}</p>
      </div>
    {:else if posts.length === 0}
      <div class="empty">
        <div class="empty__icon">∅</div>
        <h3>no posts</h3>
        <p>create your first post</p>
      </div>
    {:else}
      <div class="post-table">
        <table>
          <thead>
            <tr>
              <th>title</th>
              <th>slug</th>
              <th>status</th>
              <th>created</th>
              <th>actions</th>
            </tr>
          </thead>
          <tbody>
            {#each posts as p (p.id)}
              <tr>
                <td>{p.title}</td>
                <td>{p.slug}</td>
                <td>
                  {#if p.published}
                    <span class="badge badge-green">published</span>
                  {:else}
                    <span class="badge badge-muted">draft</span>
                  {/if}
                </td>
                <td>{fmt(p.createdAt)}</td>
                <td>
                  <div class="row-actions">
                    <button class="btn btn-ghost" onclick={() => editPost(p)}>edit</button>
                    <button class="btn btn-danger" onclick={() => del(p.id)}>del</button>
                  </div>
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  {/if}
</div>
