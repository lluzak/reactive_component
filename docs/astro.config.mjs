import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightLlmsTxt from 'starlight-llms-txt';

export default defineConfig({
  site: 'https://lluzak.github.io',
  base: '/reactive_component',
  integrations: [
    starlight({
      title: 'ReactiveComponent',
      description: 'Reactive server-rendered components for Rails via ActionCable',
      plugins: [
        starlightLlmsTxt({
          details:
            'ReactiveComponent is a Ruby gem for Rails 7.1 through 8.x. It integrates ViewComponent, Turbo Streams, and ActionCable.',
        }),
      ],
      head: [
        {
          tag: 'link',
          attrs: {
            rel: 'describedby',
            href: '/reactive_component/llms.txt',
          },
        },
      ],
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
        { label: 'Derived Entities', link: '/derived-entities/' },
        { label: 'Configuration', link: '/configuration/' },
        { label: 'Troubleshooting', link: '/troubleshooting/' },
      ],
    }),
  ],
});
