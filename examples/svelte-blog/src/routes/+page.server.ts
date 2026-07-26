import type { PageServerLoad } from './$types';
import { listPublished } from '$lib/store';

export const load: PageServerLoad = async () => {
  return {
    posts: listPublished()
  };
};
