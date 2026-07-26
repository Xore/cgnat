import type { Post } from '$lib/types';

const posts = new Map<string, Post>();

function now() {
  return Date.now();
}

function makeId() {
  return crypto.randomUUID();
}

const seedId = makeId();
posts.set(seedId, {
  id: seedId,
  title: 'Welcome to the Svelte blog',
  slug: 'welcome-to-svelte-blog',
  content: 'This blog is powered by Svelte 5 runes, SvelteKit remote functions and server data.\n\nYou can edit or delete this post from the admin panel.',
  published: true,
  createdAt: now(),
  updatedAt: now()
});

export function listPublished(): Post[] {
  return Array.from(posts.values())
    .filter((p) => p.published)
    .sort((a, b) => b.createdAt - a.createdAt);
}

export function listAll(): Post[] {
  return Array.from(posts.values()).sort((a, b) => b.createdAt - a.createdAt);
}

export function getById(id: string): Post | undefined {
  return posts.get(id);
}

export function createPost(input: Partial<Post>): Post {
  const id = makeId();
  const created = now();
  const post: Post = {
    id,
    title: input.title ?? 'Untitled',
    slug: input.slug ?? input.title?.toLowerCase().replace(/[^a-z0-9]+/g, '-') ?? id,
    content: input.content ?? '',
    published: input.published ?? false,
    createdAt: created,
    updatedAt: created
  };

  posts.set(id, post);
  return post;
}

export function updatePost(id: string, input: Partial<Post>): Post | undefined {
  const current = posts.get(id);
  if (!current) return undefined;

  const updated: Post = {
    ...current,
    ...input,
    slug: input.slug ?? current.slug,
    updatedAt: now()
  };

  posts.set(id, updated);
  return updated;
}

export function deletePost(id: string): boolean {
  return posts.delete(id);
}
