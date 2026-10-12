import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:simple_icons/simple_icons.dart';

import '../models.dart';

/// A glyph and its brand colour. A null colour means "use the text colour".
class TechGlyph {
  const TechGlyph(this.icon, [this.color]);
  final IconData icon;
  final Color? color;
}

/// The glowing tile on each card that shows what opened the port.
class TechIcon extends StatelessWidget {
  const TechIcon({
    super.key,
    required this.tech,
    required this.category,
    this.size = 32,
  });

  final TechInfo tech;
  final PortCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glyph = techGlyphs[tech.icon] ?? _fallback(category);
    final color = legibleBrandColor(glyph.color, scheme);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: tileTint),
        borderRadius: BorderRadius.circular(size * 0.25),
        border: Border.all(color: color.withValues(alpha: 0.42)),
        boxShadow: [
          // Outside the tile only: light under it would wash out the glyph.
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: size * 0.3,
            blurStyle: BlurStyle.outer,
          ),
        ],
      ),
      child: Icon(glyph.icon, size: size * 0.56, color: color),
    );
  }

  /// How strongly the tile behind the glyph is tinted with the glyph's colour.
  static const tileTint = 0.13;

  static TechGlyph _fallback(PortCategory category) => switch (category) {
    PortCategory.project => const TechGlyph(Icons.terminal_rounded),
    PortCategory.app => const TechGlyph(Icons.widgets_outlined),
    PortCategory.system => const TechGlyph(Icons.settings_outlined),
  };
}

/// Brand colours are chosen for a white page. Many are black or very dark
/// (Next.js, Express, .NET's purple) and some very pale (JavaScript yellow),
/// so this keeps the exact brand colour where it already reads on the current
/// surface and otherwise shifts only its lightness, just far enough.
Color legibleBrandColor(Color? brand, ColorScheme scheme) {
  if (brand == null) return scheme.onSurfaceVariant;
  var hsl = HSLColor.fromColor(brand);
  // Black, white and grey marks carry no hue worth keeping.
  if (hsl.saturation < 0.12) return scheme.onSurface;

  final towardsWhite = scheme.brightness == Brightness.dark;
  while (glyphContrast(hsl.toColor(), scheme) < minGlyphContrast) {
    final lightness = hsl.lightness + (towardsWhite ? 0.03 : -0.03);
    if (lightness <= 0 || lightness >= 1) return scheme.onSurface;
    hsl = hsl.withLightness(lightness);
  }
  return hsl.toColor();
}

/// The WCAG minimum for meaningful graphics.
const minGlyphContrast = 3.0;

/// Contrast ratio between a glyph in [color] and the tinted tile it sits on.
double glyphContrast(Color color, ColorScheme scheme) {
  final tile = Color.alphaBlend(
    color.withValues(alpha: TechIcon.tileTint),
    scheme.surfaceContainerLow,
  );
  final a = color.computeLuminance();
  final b = tile.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

const _windowsBlue = Color(0xff0078d4);

/// Icons for every key the tech detector can emit.
const techGlyphs = <String, TechGlyph>{
  // Not in Simple Icons (Microsoft's marks were withdrawn), so these borrow
  // Material glyphs.
  'windows': TechGlyph(Icons.window_sharp, _windowsBlue),
  'vscode': TechGlyph(Icons.code_rounded, Color(0xff007acc)),
  'edge': TechGlyph(Icons.public_rounded, Color(0xff0c8ecf)),
  'database': TechGlyph(Icons.storage_rounded, Color(0xffcc2927)),
  'terminal': TechGlyph(Icons.terminal_rounded),

  // Languages and runtimes
  'nodedotjs': TechGlyph(SimpleIcons.nodedotjs, SimpleIconColors.nodedotjs),
  'bun': TechGlyph(SimpleIcons.bun, Color(0xfffbf0df)),
  'deno': TechGlyph(SimpleIcons.deno, SimpleIconColors.deno),
  'typescript': TechGlyph(SimpleIcons.typescript, SimpleIconColors.typescript),
  'python': TechGlyph(SimpleIcons.python, SimpleIconColors.python),
  'dotnet': TechGlyph(SimpleIcons.dotnet, SimpleIconColors.dotnet),
  'blazor': TechGlyph(SimpleIcons.blazor, SimpleIconColors.blazor),
  'openjdk': TechGlyph(SimpleIcons.openjdk, Color(0xffe76f00)),
  'kotlin': TechGlyph(SimpleIcons.kotlin, SimpleIconColors.kotlin),
  'dart': TechGlyph(SimpleIcons.dart, SimpleIconColors.dart),
  'flutter': TechGlyph(SimpleIcons.flutter, SimpleIconColors.flutter),
  'ruby': TechGlyph(SimpleIcons.ruby, SimpleIconColors.ruby),
  'php': TechGlyph(SimpleIcons.php, SimpleIconColors.php),
  'go': TechGlyph(SimpleIcons.go, SimpleIconColors.go),
  'rust': TechGlyph(SimpleIcons.rust, Color(0xffdea584)),
  'erlang': TechGlyph(SimpleIcons.erlang, SimpleIconColors.erlang),
  'cplusplus': TechGlyph(SimpleIcons.cplusplus, SimpleIconColors.cplusplus),

  // JavaScript frameworks and tooling
  'vuedotjs': TechGlyph(SimpleIcons.vuedotjs, SimpleIconColors.vuedotjs),
  'react': TechGlyph(SimpleIcons.react, SimpleIconColors.react),
  'angular': TechGlyph(SimpleIcons.angular, Color(0xffdd0031)),
  'svelte': TechGlyph(SimpleIcons.svelte, SimpleIconColors.svelte),
  'solid': TechGlyph(SimpleIcons.solid, SimpleIconColors.solid),
  'preact': TechGlyph(SimpleIcons.preact, SimpleIconColors.preact),
  'lit': TechGlyph(SimpleIcons.lit, SimpleIconColors.lit),
  'qwik': TechGlyph(SimpleIcons.qwik, SimpleIconColors.qwik),
  'nextdotjs': TechGlyph(SimpleIcons.nextdotjs, SimpleIconColors.nextdotjs),
  'nuxt': TechGlyph(SimpleIcons.nuxt, SimpleIconColors.nuxt),
  'remix': TechGlyph(SimpleIcons.remix, SimpleIconColors.remix),
  'reactrouter': TechGlyph(SimpleIcons.reactrouter, SimpleIconColors.reactrouter),
  'astro': TechGlyph(SimpleIcons.astro, SimpleIconColors.astro),
  'gatsby': TechGlyph(SimpleIcons.gatsby, SimpleIconColors.gatsby),
  'nestjs': TechGlyph(SimpleIcons.nestjs, SimpleIconColors.nestjs),
  'express': TechGlyph(SimpleIcons.express, SimpleIconColors.express),
  'fastify': TechGlyph(SimpleIcons.fastify, SimpleIconColors.fastify),
  'koa': TechGlyph(SimpleIcons.koa, SimpleIconColors.koa),
  'hono': TechGlyph(SimpleIcons.hono, SimpleIconColors.hono),
  'adonisjs': TechGlyph(SimpleIcons.adonisjs, SimpleIconColors.adonisjs),
  'strapi': TechGlyph(SimpleIcons.strapi, SimpleIconColors.strapi),
  'apollographql': TechGlyph(SimpleIcons.apollographql, SimpleIconColors.apollographql),
  'trpc': TechGlyph(SimpleIcons.trpc, SimpleIconColors.trpc),
  'socketdotio': TechGlyph(SimpleIcons.socketdotio, SimpleIconColors.socketdotio),
  'vite': TechGlyph(SimpleIcons.vite, SimpleIconColors.vite),
  'vitest': TechGlyph(SimpleIcons.vitest, SimpleIconColors.vitest),
  'vitepress': TechGlyph(SimpleIcons.vitepress, SimpleIconColors.vitepress),
  'webpack': TechGlyph(SimpleIcons.webpack, SimpleIconColors.webpack),
  'rollupdotjs': TechGlyph(SimpleIcons.rollupdotjs, SimpleIconColors.rollupdotjs),
  'esbuild': TechGlyph(SimpleIcons.esbuild, SimpleIconColors.esbuild),
  'docusaurus': TechGlyph(SimpleIcons.docusaurus, SimpleIconColors.docusaurus),
  'storybook': TechGlyph(SimpleIcons.storybook, SimpleIconColors.storybook),
  'eleventy': TechGlyph(SimpleIcons.eleventy, SimpleIconColors.eleventy),
  'expo': TechGlyph(SimpleIcons.expo, SimpleIconColors.expo),
  'jest': TechGlyph(SimpleIcons.jest, SimpleIconColors.jest),
  'cypress': TechGlyph(SimpleIcons.cypress, SimpleIconColors.cypress),
  'eslint': TechGlyph(SimpleIcons.eslint, SimpleIconColors.eslint),
  'nodemon': TechGlyph(SimpleIcons.nodemon, SimpleIconColors.nodemon),
  'pm2': TechGlyph(SimpleIcons.pm2, SimpleIconColors.pm2),
  'tsnode': TechGlyph(SimpleIcons.tsnode, SimpleIconColors.tsnode),
  'cloudflareworkers': TechGlyph(
    SimpleIcons.cloudflareworkers,
    SimpleIconColors.cloudflareworkers,
  ),
  'cloudflare': TechGlyph(SimpleIcons.cloudflare, SimpleIconColors.cloudflare),
  'firebase': TechGlyph(SimpleIcons.firebase, SimpleIconColors.firebase),
  'supabase': TechGlyph(SimpleIcons.supabase, SimpleIconColors.supabase),
  'prisma': TechGlyph(SimpleIcons.prisma, SimpleIconColors.prisma),
  'claude': TechGlyph(SimpleIcons.claude, SimpleIconColors.claude),

  // Python
  'django': TechGlyph(SimpleIcons.django, Color(0xff0c9b6d)),
  'flask': TechGlyph(SimpleIcons.flask, SimpleIconColors.flask),
  'fastapi': TechGlyph(SimpleIcons.fastapi, SimpleIconColors.fastapi),
  'streamlit': TechGlyph(SimpleIcons.streamlit, SimpleIconColors.streamlit),
  'gradio': TechGlyph(SimpleIcons.gradio, SimpleIconColors.gradio),
  'jupyter': TechGlyph(SimpleIcons.jupyter, SimpleIconColors.jupyter),
  'materialformkdocs': TechGlyph(
    SimpleIcons.materialformkdocs,
    SimpleIconColors.materialformkdocs,
  ),
  'tensorflow': TechGlyph(SimpleIcons.tensorflow, SimpleIconColors.tensorflow),
  'mlflow': TechGlyph(SimpleIcons.mlflow, SimpleIconColors.mlflow),
  'apacheairflow': TechGlyph(SimpleIcons.apacheairflow, SimpleIconColors.apacheairflow),
  'celery': TechGlyph(SimpleIcons.celery, SimpleIconColors.celery),
  'locust': TechGlyph(SimpleIcons.locust, SimpleIconColors.locust),
  'gunicorn': TechGlyph(SimpleIcons.gunicorn, SimpleIconColors.gunicorn),
  'aiohttp': TechGlyph(SimpleIcons.aiohttp, SimpleIconColors.aiohttp),
  'sanic': TechGlyph(SimpleIcons.sanic, SimpleIconColors.sanic),

  // JVM, Ruby, PHP, Erlang, Rust, Go
  'springboot': TechGlyph(SimpleIcons.springboot, SimpleIconColors.springboot),
  'gradle': TechGlyph(SimpleIcons.gradle, Color(0xff1ba8cb)),
  'apachemaven': TechGlyph(SimpleIcons.apachemaven, SimpleIconColors.apachemaven),
  'apachetomcat': TechGlyph(SimpleIcons.apachetomcat, SimpleIconColors.apachetomcat),
  'apachekafka': TechGlyph(SimpleIcons.apachekafka, SimpleIconColors.apachekafka),
  'apachecassandra': TechGlyph(
    SimpleIcons.apachecassandra,
    SimpleIconColors.apachecassandra,
  ),
  'elasticsearch': TechGlyph(SimpleIcons.elasticsearch, SimpleIconColors.elasticsearch),
  'quarkus': TechGlyph(SimpleIcons.quarkus, SimpleIconColors.quarkus),
  'ktor': TechGlyph(SimpleIcons.ktor, SimpleIconColors.ktor),
  'jenkins': TechGlyph(SimpleIcons.jenkins, SimpleIconColors.jenkins),
  'neo4j': TechGlyph(SimpleIcons.neo4j, SimpleIconColors.neo4j),
  'rubyonrails': TechGlyph(SimpleIcons.rubyonrails, SimpleIconColors.rubyonrails),
  'jekyll': TechGlyph(SimpleIcons.jekyll, SimpleIconColors.jekyll),
  'puma': TechGlyph(SimpleIcons.puma, SimpleIconColors.puma),
  'laravel': TechGlyph(SimpleIcons.laravel, SimpleIconColors.laravel),
  'symfony': TechGlyph(SimpleIcons.symfony, SimpleIconColors.symfony),
  'rabbitmq': TechGlyph(SimpleIcons.rabbitmq, SimpleIconColors.rabbitmq),
  'phoenixframework': TechGlyph(
    SimpleIcons.phoenixframework,
    SimpleIconColors.phoenixframework,
  ),
  'tauri': TechGlyph(SimpleIcons.tauri, SimpleIconColors.tauri),
  'actix': TechGlyph(SimpleIcons.actix, SimpleIconColors.actix),
  'rocket': TechGlyph(SimpleIcons.rocket, SimpleIconColors.rocket),
  'gin': TechGlyph(SimpleIcons.gin, SimpleIconColors.gin),

  // Databases and infrastructure
  'postgresql': TechGlyph(SimpleIcons.postgresql, SimpleIconColors.postgresql),
  'mysql': TechGlyph(SimpleIcons.mysql, SimpleIconColors.mysql),
  'mariadb': TechGlyph(SimpleIcons.mariadb, Color(0xffc0765a)),
  'mongodb': TechGlyph(SimpleIcons.mongodb, SimpleIconColors.mongodb),
  'redis': TechGlyph(SimpleIcons.redis, SimpleIconColors.redis),
  'influxdb': TechGlyph(SimpleIcons.influxdb, SimpleIconColors.influxdb),
  'clickhouse': TechGlyph(SimpleIcons.clickhouse, SimpleIconColors.clickhouse),
  'meilisearch': TechGlyph(SimpleIcons.meilisearch, SimpleIconColors.meilisearch),
  'qdrant': TechGlyph(SimpleIcons.qdrant, SimpleIconColors.qdrant),
  'minio': TechGlyph(SimpleIcons.minio, SimpleIconColors.minio),
  'etcd': TechGlyph(SimpleIcons.etcd, SimpleIconColors.etcd),
  'consul': TechGlyph(SimpleIcons.consul, SimpleIconColors.consul),
  'vault': TechGlyph(SimpleIcons.vault, SimpleIconColors.vault),
  'grafana': TechGlyph(SimpleIcons.grafana, SimpleIconColors.grafana),
  'prometheus': TechGlyph(SimpleIcons.prometheus, SimpleIconColors.prometheus),
  'nginx': TechGlyph(SimpleIcons.nginx, SimpleIconColors.nginx),
  'apache': TechGlyph(SimpleIcons.apache, SimpleIconColors.apache),
  'caddy': TechGlyph(SimpleIcons.caddy, SimpleIconColors.caddy),
  'traefikproxy': TechGlyph(SimpleIcons.traefikproxy, SimpleIconColors.traefikproxy),
  'ngrok': TechGlyph(SimpleIcons.ngrok, SimpleIconColors.ngrok),
  'tailscale': TechGlyph(SimpleIcons.tailscale, SimpleIconColors.tailscale),
  'hugo': TechGlyph(SimpleIcons.hugo, SimpleIconColors.hugo),
  'docker': TechGlyph(SimpleIcons.docker, SimpleIconColors.docker),
  'podman': TechGlyph(SimpleIcons.podman, SimpleIconColors.podman),
  'kubernetes': TechGlyph(SimpleIcons.kubernetes, SimpleIconColors.kubernetes),
  'linux': TechGlyph(SimpleIcons.linux, SimpleIconColors.linux),
  // Apple's own colour is black, which the dark would swallow.
  'apple': TechGlyph(SimpleIcons.apple, Color(0xffa2aaad)),
  'qemu': TechGlyph(SimpleIcons.qemu, SimpleIconColors.qemu),
  'vmware': TechGlyph(SimpleIcons.vmware, SimpleIconColors.vmware),
  'virtualbox': TechGlyph(SimpleIcons.virtualbox, SimpleIconColors.virtualbox),

  // Developer tools and everyday apps
  'cursor': TechGlyph(SimpleIcons.cursor, SimpleIconColors.cursor),
  'zedindustries': TechGlyph(SimpleIcons.zedindustries, SimpleIconColors.zedindustries),
  'jetbrains': TechGlyph(SimpleIcons.jetbrains, SimpleIconColors.jetbrains),
  'intellijidea': TechGlyph(SimpleIcons.intellijidea, SimpleIconColors.intellijidea),
  'webstorm': TechGlyph(SimpleIcons.webstorm, SimpleIconColors.webstorm),
  'pycharm': TechGlyph(SimpleIcons.pycharm, SimpleIconColors.pycharm),
  'rider': TechGlyph(SimpleIcons.rider, SimpleIconColors.rider),
  'android': TechGlyph(SimpleIcons.android, SimpleIconColors.android),
  'androidstudio': TechGlyph(SimpleIcons.androidstudio, SimpleIconColors.androidstudio),
  'ollama': TechGlyph(SimpleIcons.ollama, SimpleIconColors.ollama),
  'postman': TechGlyph(SimpleIcons.postman, SimpleIconColors.postman),
  'insomnia': TechGlyph(SimpleIcons.insomnia, SimpleIconColors.insomnia),
  'git': TechGlyph(SimpleIcons.git, SimpleIconColors.git),
  'googlechrome': TechGlyph(SimpleIcons.googlechrome, SimpleIconColors.googlechrome),
  'firefoxbrowser': TechGlyph(SimpleIcons.firefoxbrowser, SimpleIconColors.firefoxbrowser),
  'brave': TechGlyph(SimpleIcons.brave, SimpleIconColors.brave),
  'opera': TechGlyph(SimpleIcons.opera, SimpleIconColors.opera),
  'figma': TechGlyph(SimpleIcons.figma, SimpleIconColors.figma),
  'dropbox': TechGlyph(SimpleIcons.dropbox, SimpleIconColors.dropbox),
  'zoom': TechGlyph(SimpleIcons.zoom, SimpleIconColors.zoom),
  'steam': TechGlyph(SimpleIcons.steam, Color(0xff66c0f4)),
  'spotify': TechGlyph(SimpleIcons.spotify, SimpleIconColors.spotify),
  'discord': TechGlyph(SimpleIcons.discord, SimpleIconColors.discord),
  'teamviewer': TechGlyph(SimpleIcons.teamviewer, SimpleIconColors.teamviewer),
  'nvidia': TechGlyph(SimpleIcons.nvidia, SimpleIconColors.nvidia),
  'godotengine': TechGlyph(SimpleIcons.godotengine, SimpleIconColors.godotengine),
};
