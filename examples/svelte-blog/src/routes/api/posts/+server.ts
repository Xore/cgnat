import type { RequestHandler } from '@sveltejs/kit';
import { listPublished, getById } from '$lib/store';

export const GET: RequestHandler = async ({ params }) => {
  if (params.id) {
    const post = getById(params.id);
    if (!post || !post.published) {
      return new Response(JSON.stringify({ error: 'Not found' }), { status: 404 });
    }
    return new Response(JSON.stringify(post), {
      headers: { 'content-type': 'application/json' }
    });
  }

  const posts = listPublished();
  return new Response(JSON.stringify(posts), {
    headers: { 'content-type': 'application/json' }
  });
};
