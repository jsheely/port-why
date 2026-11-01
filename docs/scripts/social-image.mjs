// Render the share image from the real app assets. Run: npm run social-image
import { readFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const root = new URL('../', import.meta.url);
const screenshot = await sharp(await readFile(new URL('screenshot.png', root)))
  .resize({ width: 1000 }).png().toBuffer();
const icon = await readFile(new URL('../../packaging/icons/128.png', import.meta.url));
const data = (buffer) => `data:image/png;base64,${buffer.toString('base64')}`;
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
<defs>
  <linearGradient id="night" x2="1" y2="1"><stop stop-color="#071722"/><stop offset=".55" stop-color="#04050d"/><stop offset="1" stop-color="#1c0d26"/></linearGradient>
  <linearGradient id="edge"><stop stop-color="#19e3ff"/><stop offset=".65" stop-color="#a573ff"/><stop offset="1" stop-color="#ff2e7e"/></linearGradient>
  <linearGradient id="fade" x2="0" y2="1"><stop offset=".5" stop-color="#04050d" stop-opacity="0"/><stop offset="1" stop-color="#04050d" stop-opacity=".85"/></linearGradient>
  <clipPath id="screen"><path d="M650 155H1198V544H650Q632 544 632 526V173Q632 155 650 155Z"/></clipPath>
</defs>
<rect width="1200" height="630" fill="url(#night)"/>
<g fill="none" stroke-width="1">
  <path d="M0 110H32L58 136V470L30 498H0M0 121H24L46 143V460L20 486H0" stroke="#19e3ff" opacity=".25"/>
  <path d="M1200 62H1130L1105 87H828L803 112H665M1200 76H1136L1111 101H834L809 126H710" stroke="#ff2e7e" opacity=".3"/>
  <path d="M440 630V601L464 577H550L574 553H610M455 630V609L480 585H558" stroke="#a573ff" opacity=".25"/>
</g>
<rect x="0" y="0" width="1200" height="4" fill="url(#edge)"/>
<image href="${data(icon)}" x="65" y="55" width="52" height="52"/>
<g font-family="Bahnschrift, Segoe UI, sans-serif">
  <text x="134" y="89" fill="#e9f0ff" font-size="27" font-weight="700" letter-spacing="6">PORT WHY</text>
  <text x="68" y="164" fill="#19e3ff" font-size="13" font-weight="600" letter-spacing="3">YOUR LOCALHOST, EXPLAINED</text>
  <text x="64" y="241" fill="#e9f0ff" font-size="60" font-weight="700">What is holding</text>
  <text x="64" y="311" fill="#19e3ff" font-size="60" font-weight="700">that port open?</text>
  <text x="68" y="369" fill="#c2cce2" font-size="23">Meet the process. Find the project.</text>
  <text x="68" y="401" fill="#c2cce2" font-size="23">Get back to building.</text>
</g>
<g font-family="Cascadia Mono, Consolas, monospace" font-size="13">
  <rect x="68" y="442" width="255" height="35" rx="5" fill="#19e3ff0d" stroke="#19e3ff55"/>
  <circle cx="83" cy="459" r="3" fill="#35ff9f"/>
  <text x="97" y="464" fill="#a9f5ff">PROCESS → PROJECT → PATH</text>
</g>
<g clip-path="url(#screen)">
  <rect x="632" y="155" width="568" height="389" fill="#0a0e22"/>
  <image href="${data(screenshot)}" x="644" y="167" width="1000" height="791.14"/>
  <rect x="632" y="155" width="568" height="389" fill="url(#fade)"/>
</g>
<path d="M1199 155H650Q632 155 632 173V526Q632 544 650 544H1199" fill="none" stroke="url(#edge)" stroke-opacity=".7"/>
<g font-family="Cascadia Mono, Consolas, monospace">
  <text x="653" y="137" fill="#909dc6" font-size="11" letter-spacing="2">THE LOCALHOST DECK</text>
  <text x="68" y="563" fill="#e9f0ff" font-size="13" letter-spacing="1">WINDOWS <tspan fill="#4b5784"> / </tspan> macOS <tspan fill="#4b5784"> / </tspan> LINUX</text>
  <text x="68" y="596" fill="#909dc6" font-size="12">jsheely.github.io/port-why</text>
  <text x="1146" y="592" text-anchor="end" fill="#909dc6" font-size="10" letter-spacing="1">ACTUAL APP · DEMO DATA</text>
</g>
</svg>`;
await mkdir(new URL('public/', root), { recursive: true });
await sharp(Buffer.from(svg)).png().toFile(fileURLToPath(new URL('public/og-image.png', root)));
console.log('Rendered public/og-image.png (1200 × 630)');
