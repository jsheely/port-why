import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

const socialBase = (process.env.DOCS_BASE ?? '/port-why/').replace(/\/$/, '');
const socialImage = new URL(`${socialBase}/og-image.png`, process.env.DOCS_SITE || 'https://jsheely.github.io').href;
const socialAlt = 'Port Why: What is holding that port open? The app shows ports, frameworks, projects, and folders. Available for Windows, macOS, and Linux.';

export default defineConfig({
  // Set these for the target host; links and assets also work under a subpath.
  site: process.env.DOCS_SITE || undefined,
  base: process.env.DOCS_BASE || '/',
  integrations: [starlight({
    title: 'Port Why',
    description: 'Your localhost, explained. Documentation for Port Why.',
    logo: { src: './src/assets/icon.png' },
    favicon: '/favicon.png',
    head: [
      { tag: 'meta', attrs: { property: 'og:image', content: socialImage } },
      { tag: 'meta', attrs: { property: 'og:image:type', content: 'image/png' } },
      { tag: 'meta', attrs: { property: 'og:image:width', content: '1200' } },
      { tag: 'meta', attrs: { property: 'og:image:height', content: '630' } },
      { tag: 'meta', attrs: { property: 'og:image:alt', content: socialAlt } },
      { tag: 'meta', attrs: { name: 'twitter:image', content: socialImage } },
      { tag: 'meta', attrs: { name: 'twitter:image:alt', content: socialAlt } },
    ],
    customCss: ['./src/styles/custom.css'],
    components: {
      ThemeSelect: './src/components/ThemeSelect.astro',
      ThemeProvider: './src/components/ThemeProvider.astro',
      Hero: './src/components/Hero.astro',
    },
    social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/jsheely/port-why' }],
    editLink: { baseUrl: 'https://github.com/jsheely/port-why/edit/main/docs/' },
    sidebar: [
      { label: 'Start here', items: [
        { label: 'Overview', slug: '' },
        { label: 'Installation', slug: 'getting-started/installation' },
        { label: 'Your first scan', slug: 'getting-started/first-scan' },
      ] },
      { label: 'Using Port Why', items: [
        { label: 'Find & inspect ports', slug: 'guides/find-ports' },
        { label: 'Docker & WSL', slug: 'guides/docker-wsl' },
        { label: 'Troubleshooting', slug: 'guides/troubleshooting' },
      ] },
      { label: 'Under the hood', items: [
        { label: 'How scanning works', slug: 'reference/architecture' },
        { label: 'Keyboard shortcuts', slug: 'reference/shortcuts' },
        { label: 'Development', slug: 'reference/development' },
      ] },
    ],
  })],
});
