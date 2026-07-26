import { ref } from 'vue';

// Admin token as a shared reactive ref so the header badge and every admin
// view stay in sync across route changes.
export const adminToken = ref(null);

// Thin wrapper around fetch that injects the admin header and surfaces API
// errors. Mirrors the endpoints in ../../app.js exactly.
export async function api(method, path, body) {
  const headers = { 'Content-Type': 'application/json' };
  if (adminToken.value) headers['X-Admin-Token'] = adminToken.value;

  const res = await fetch(path, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined
  });

  // DELETE returns 204 with no body; json() then rejects and we fall back to {}.
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(json.error || res.statusText);
  return json;
}
