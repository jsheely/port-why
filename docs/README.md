# Port Why documentation

Astro Starlight site, kept alongside the existing README screenshots.

```sh
cd docs
npm ci
npm run dev
```

Use Node.js 22.23.4+ (Node 24 recommended). `npm run build` runs Astro's type/content checks, builds static pages, and generates the Pagefind search index. `npm run preview` serves the production build, including search.

Content lives in `src/content/docs/`. Navigation is configured in `astro.config.mjs`. The theme copies the app and promo palette, fonts, and glass treatments. `src/scripts/port-backdrop.ts` draws the homepage's cyberpunk hardware panels, traveling circuit signals, and port telemetry, with pointer/scroll parallax, reduced-motion support, and hidden-tab suspension. It uses Canvas 2D without a WebGL dependency.

## GitHub Pages

`.github/workflows/docs.yml` builds pull requests and publishes docs changes on
`main` to **https://jsheely.github.io/port-why/**. You can also run the workflow
manually on `main`. Other branches can build manually but cannot deploy.

One-time repository setup: **Settings → Pages → Build and deployment → Source →
GitHub Actions**. If the `github-pages` environment has deployment restrictions,
allow `main`. The deploy job uses GitHub's token with `pages: write` and
`id-token: write`; no personal token is needed.

The workflow sets `DOCS_SITE=https://jsheely.github.io` and
`DOCS_BASE=/port-why/` so assets, search, links, and the sitemap use the project
URL. Local development remains at `/`. For another host, override these values
and deploy `dist/` to that static host.

Keep the root `screenshot.png` and `details.png` paths intact: the application README also uses them. The website imports and optimizes those same images.

Regenerate the homepage screenshot on Windows with `flutter test tool/capture_docs.dart`
from the repository root. This renders the real Flutter widgets with demo data at
3792 × 3000 pixels (3×), loading Bahnschrift, Cascadia Mono, and Segoe UI from
Windows Fonts. The homepage serves responsive PNGs to preserve small text and icons.

Reference: [Starlight custom styles](https://starlight.astro.build/guides/css-and-tailwind/).
