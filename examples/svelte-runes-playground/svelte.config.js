import type { Config } from 'sveltekit';

const config: Config = {
  kit: {
    alias: {
      $lib: 'src/lib'
    }
  }
};

export default config;
