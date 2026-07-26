import adapter from '@sveltejs/adapter-node';

/** @type {import('@sveltejs/kit').Config} */
const config = {
  kit: {
    // Node adapter: the app has server routes (+page.server.ts, api/+server.ts)
    // and runs via `npm run dev` in the CGNAT container.
    adapter: adapter(),
    alias: {
      $lib: 'src/lib'
    }
  }
};

export default config;
