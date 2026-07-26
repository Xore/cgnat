import type { LayoutLoad } from './$types';

export const load: LayoutLoad = async ({ fetch }) => {
  const res = await fetch('/api/hyped');
  const data = await res.json();

  return {
    hyped: data
  };
};
