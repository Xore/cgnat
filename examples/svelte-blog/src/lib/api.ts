import { writable } from 'svelte/store';

// Admin token in a store so the header badge and admin view stay in sync.
export const adminToken = writable<string | null>(null);

let token: string | null = null;
adminToken.subscribe((value) => {
  token = value;
});

// Thin wrapper around fetch that injects the admin header and surfaces API
// errors. Talks to the SvelteKit server routes under /api.
export async function api<T = unknown>(method: string, path: string, body?: unknown): Promise<T> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (token) headers['X-Admin-Token'] = token;

  const res = await fetch(path, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined
  });

  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error((json as { error?: string }).error || res.statusText);
  return json as T;
}
