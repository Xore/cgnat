import type { RequestHandler } from '@sveltejs/kit';

const SECRET = process.env.ADMIN_PASSWORD ?? 'change-me-svelte';

export const POST: RequestHandler = async ({ request }) => {
  const { password } = await request.json();
  if (!password || password !== SECRET) {
    return new Response(JSON.stringify({ error: 'Invalid password' }), {
      status: 401,
      headers: { 'content-type': 'application/json' }
    });
  }

  return new Response(JSON.stringify({ ok: true, token: SECRET }), {
    headers: { 'content-type': 'application/json' }
  });
};
