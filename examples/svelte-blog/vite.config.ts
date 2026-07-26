import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [sveltekit()],
  server: {
    port: 4174,
    strictPort: false,
    // The dev server sits behind Cloudflare → Traefik → socat, which forward the
    // real Host header. Vite blocks unknown hosts, so allow the public domain(s).
    // A leading dot ('.xore.rocks') allows the domain and all its subdomains.
    allowedHosts: ['.xore.rocks']
  }
});
