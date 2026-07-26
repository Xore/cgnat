import type { RequestHandler } from '@sveltejs/kit';
import { createPost, updatePost, deletePost, listAll } from '$lib/store';

const SECRET = process.env.ADMIN_PASSWORD ?? 'change-me-svelte';

function guard(headers: Headers): Response | null {
  const token = headers.get('x-admin-token');
  if (token !== SECRET) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { 'content-type': 'application/json' }
    });
  }
  return null;
}

export const GET: RequestHandler = async ({ request }) => {
  const fail = guard(request.headers);
  if (fail) return fail;

  return new Response(JSON.stringify(listAll()), {
    headers: { 'content-type': 'application/json' }
  });
};

export const POST: RequestHandler = async ({ request }) => {
  const fail = guard(request.headers);
  if (fail) return fail;

  const body = await request.json();
  const post = createPost(body);
  return new Response(JSON.stringify(post), {
    status: 201,
    headers: { 'content-type': 'application/json' }
  });
};

export const PUT: RequestHandler = async ({ request }) => {
  const fail = guard(request.headers);
  if (fail) return fail;

  const body = await request.json();
  if (!body.id) {
    return new Response(JSON.stringify({ error: 'id required' }), { status: 400 });
  }
  const updated = updatePost(body.id, body);
  if (!updated) {
    return new Response(JSON.stringify({ error: 'Not found' }), { status: 404 });
  }
  return new Response(JSON.stringify(updated), {
    headers: { 'content-type': 'application/json' }
  });
};

export const DELETE: RequestHandler = async ({ request }) => {
  const fail = guard(request.headers);
  if (fail) return fail;

  const body = await request.json();
  if (!body.id) {
    return new Response(JSON.stringify({ error: 'id required' }), { status: 400 });
  }
  const ok = deletePost(body.id);
  return new Response(JSON.stringify({ ok }), {
    headers: { 'content-type': 'application/json' }
  });
};
