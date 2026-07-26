import type { RequestHandler } from '@sveltejs/kit';

export const GET: RequestHandler = async () => {
  const hyped = {
    runes: ['$state', '$derived', '$effect'],
    features: ['server data', 'remote functions', 'runes'],
    timestamp: Date.now()
  };

  return new Response(JSON.stringify(hyped), {
    headers: {
      'content-type': 'application/json'
    }
  });
};
