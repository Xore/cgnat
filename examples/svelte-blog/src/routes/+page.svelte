<script lang="ts">
  import type { PageData } from './$types';

  let { data }: { data: PageData } = $props();

  const fmt = (t: number) =>
    new Date(t).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
</script>

<div class="view active">
  <h1 class="page-title">ls ./posts</h1>

  {#if data.posts.length === 0}
    <div class="empty">
      <div class="empty__icon">∅</div>
      <h3>no posts yet</h3>
      <p>published posts will appear here</p>
    </div>
  {:else}
    <div class="post-grid">
      {#each data.posts as post (post.id)}
        <a class="post-card" href={`/post/${post.id}`}>
          <h2 class="post-card__title">{post.title}</h2>
          <div class="post-card__meta">{fmt(post.createdAt)}</div>
          <p class="post-card__excerpt">{post.content}</p>
          <div class="post-card__arrow">read <span>→</span></div>
        </a>
      {/each}
    </div>
  {/if}
</div>
