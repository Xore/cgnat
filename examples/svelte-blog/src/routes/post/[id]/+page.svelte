<script lang="ts">
  import type { PageData } from './$types';

  let { data }: { data: PageData } = $props();

  const fmt = (t: number) => new Date(t).toLocaleString();
</script>

<div class="view active">
  <a class="post-single__back" href="/">← cd ..</a>
  <h1 class="post-single__title">{data.post.title}</h1>
  <div class="post-single__meta">{fmt(data.post.createdAt)} · /{data.post.slug}</div>
  <div class="post-single__body">{data.post.content}</div>
</div>
