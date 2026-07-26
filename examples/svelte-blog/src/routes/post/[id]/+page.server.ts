import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { getById } from '$lib/store';

export const load: PageServerLoad = async ({ params }) => {
  const post = getById(params.id ?? '');

  if (!post || !post.published) {
    throw error(404, 'Not found');
  }

  return { post };
};
