import type { ServerLoad } from './$types';

export const load: ServerLoad = async ({ fetch }) => {
  const res = await fetch('/api/hyped');
  const data = await res.json();

  return {
    hyped: data
  };
};
