import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://lluzak.github.io',
  base: '/reactive_component',
  integrations: [
    starlight({
      title: 'ReactiveComponent',
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/lluzak/reactive_component',
        },
      ],
      customCss: ['./src/styles/custom.css'],
      sidebar: [
        { label: 'Home', link: '/' },
        { label: 'Installation', link: '/installation/' },
        { label: 'Quick Start', link: '/quick-start/' },
        { label: 'Configuration', link: '/configuration/' },
        { label: 'DSL Reference', link: '/dsl-reference/' },
      ],
    }),
  ],
});
