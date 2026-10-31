# Port Why documentation

Astro Starlight site, kept alongside the existing README screenshots.

```sh
cd docs
npm ci
npm run dev
```

Use Node.js 22.23.4+ (Node 24 recommended). `npm run build` runs Astro's type/content checks, builds static pages, and generates the Pagefind search index. `npm run preview` serves the production build, including search.

Content lives in `src/content/docs/`. Navigation is configured in `astro.config.mjs`. The theme copies the app and promo palette, fonts, and glass treatments. `src/scripts/port-backdrop.ts` draws the homepage's perspective circuit field, with pointer/scroll parallax, reduced-motion support, and hidden-tab suspension. It uses Canvas 2D to project 3D coordinates without a WebGL dependency.

For hosting, set `DOCS_SITE` to the production origin and optionally `DOCS_BASE` to a subpath (for example `/port-why/`) before building. Deploy `dist/` with a static host. No hosting target is assumed or deployed by this project.

Keep the root `screenshot.png` and `details.png` paths intact: the application README also uses them. The website imports and optimizes those same images.

Reference: [Starlight custom styles](https://starlight.astro.build/guides/css-and-tailwind/).
