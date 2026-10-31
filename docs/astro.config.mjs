import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  // Set these for the target host; links and assets also work under a subpath.
  site: process.env.DOCS_SITE || undefined,
  base: process.env.DOCS_BASE || '/',
  integrations: [starlight({
    title: 'Port Why',
    description: 'Your localhost, explained. Documentation for Port Why.',
    logo: { src: './src/assets/icon.png' },
    favicon: '/favicon.png',
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
