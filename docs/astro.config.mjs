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
        { label: 'How It Works', link: '/how-it-works/' },
        { label: 'DSL Reference', link: '/dsl-reference/' },
        { label: 'Nested Components', link: '/nested-components/' },
        { label: 'Collections & Loops', link: '/collections/' },
        { label: 'Configuration', link: '/configuration/' },
        { label: 'Troubleshooting', link: '/troubleshooting/' },
      ],
    }),
  ],
});
