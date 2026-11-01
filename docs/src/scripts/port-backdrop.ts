/** Layered cyberpunk hardware: cut-metal panels, neon traces, and port telemetry.
 * Canvas keeps the decorative scene lightweight; depth comes from parallax.
 */
export function startPortBackdrop(canvas: HTMLCanvasElement) {
  const context = canvas.getContext('2d');
  if (!context) return;
  const ctx = context;
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  const colors = ['#19e3ff', '#a573ff', '#ff2e7e'];
  let width = 0, height = 0, frame = 0, time = 0, last = 0;
  let pointerX = 0, pointerY = 0;
  let cameraX = 0, cameraY = 0;
  let disposed = false;

  const ports = ['3000', '5173', '8080', '5432', '6379', '8000', '443', '4200'];
  // Stable pseudo-random samples keep glitches repeatable within a short burst.
  const noise = (seed: number) => {
    const value = Math.sin(seed * 127.1 + 311.7) * 43758.5453;
    return value - Math.floor(value);
  };
  const smooth = (value: number) => {
    const t = Math.max(0, Math.min(1, value));
    return t * t * (3 - 2 * t);
  };

  function drawTransfers(rail: number) {
    // Scheduled transmissions on fixed buses, moving at full display frame rate.
    const count = width < 600 ? 12 : 26;
    const lanes = count / 2;
    const snap = (value: number) => Math.round(value / 4) * 4;
    for (let i = 0; i < count; i++) {
      const lane = Math.floor(i / 2);
      const clock = time + lane * .75 + (i % 2) * 8;
      const cycle = Math.floor(clock / 16);
      const age = clock % 16;
      if (age > 12) continue;
      const direction = i % 2 ? -1 : 1;
      const start = rail * .7;
      const distance = width - start * 2;
      const baseline = snap(height * (.14 + lane / (lanes - 1) * .72));
      const bend = lane % 2 ? -16 : 16;
      const ramp = (t: number, from: number, duration: number) => Math.max(0, Math.min(1, (t - from) / duration));
      const point = (t: number) => {
        const along = .32 * ramp(t, 1, 2) + .36 * ramp(t, 4.25, 2.25) + .32 * ramp(t, 8, 2);
        return {
          x: direction > 0 ? start + distance * along : width - start - distance * along,
          y: baseline + bend * ramp(t, 3.75, .5) - bend * ramp(t, 7.5, .5),
        };
      };
      // Burst decisions are independent of digit glitches. Prefer the exposed
      // outer legs: fixed center junctions were hidden behind the hero/cards.
      const explosionSeed = i * 173 + cycle * 619 + 47;
      const breaks = noise(explosionSeed) < .45;
      const burstLeg = noise(explosionSeed + 1);
      const breakAt = (burstLeg < .45 ? 1.15 : burstLeg < .9 ? 8.35 : 4.5)
        + noise(explosionSeed + 2) * 1.2;
      const shattered = breaks && age >= breakAt;
      const p = point(shattered ? breakAt : age);
      const color = colors[(i + cycle) % colors.length];
      const port = ':' + ports[(i * 3 + cycle) % ports.length];
      const envelope = smooth(age / .5) * (1 - smooth((age - 10.5) / 1.5));
      // Low contrast through the reading column, stronger as signals approach hardware.
      const edge = Math.abs(p.x / width - .5) * 2;
      const alpha = envelope * (.16 + .3 * edge * edge);
      ctx.save();
      ctx.fillStyle = ctx.strokeStyle = color;
      ctx.font = `${width < 600 ? 11 : 14}px "Cascadia Mono", Consolas, monospace`;
      // Junctions and short dashed bus segments expose the routing structure.
      ctx.globalAlpha = .06;
      ctx.lineWidth = 1;
      ctx.setLineDash([2, 8]);
      ctx.beginPath();
      for (const t of [0, 3, 4.25, 6.5, 8, 10]) {
        const node = point(t);
        if (t === 0) ctx.moveTo(node.x, node.y); else ctx.lineTo(node.x, node.y);
      }
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.globalAlpha = .18;
      for (const t of [3, 6.5]) {
        const node = point(t);
        ctx.strokeRect(node.x - 3, node.y - 3, 6, 6);
      }
      if (shattered) {
        const elapsed = age - breakAt;
        if (elapsed < 2.8) {
          // Deterministic debris: no random per-frame noise, flash, or screen shake.
          const fade = 1 - smooth(elapsed / 2.8);
          const burstAlpha = Math.min(.7, .3 + edge * .4);
          for (let pixel = 0; pixel < 36; pixel++) {
            const angle = pixel * 2.39996 + noise(explosionSeed + 3) * Math.PI * 2;
            const speed = 24 + noise(explosionSeed + pixel * 11) * 65;
            // Fast initial breakup, then the fragments slow and dissolve.
            const travel = (1 - Math.exp(-elapsed * 1.6)) * speed;
            const x = p.x + (pixel % 9 - 4) * 5 + Math.cos(angle) * travel;
            const y = p.y - 10 + (Math.floor(pixel / 9) - 1.5) * 5 + Math.sin(angle) * travel;
            ctx.fillStyle = pixel % 4 === 0 ? '#ff2e7e' : color;
            ctx.globalAlpha = burstAlpha * fade * (.6 + pixel % 3 * .2);
            const size = pixel % 4 === 0 ? 4 : 2;
            ctx.fillRect(x, y, size, size);
          }
        }
      } else {
        ctx.globalAlpha = alpha;
        ctx.textAlign = 'center';
        // Occasional transmission corruption, only while a packet is moving.
        // Each packet gets its own short burst; never flash the entire scene.
        const moving = (age > 1 && age < 3) || (age > 4.25 && age < 6.5) || (age > 8 && age < 10);
        const window = Math.floor(clock / 1.7);
        const seed = i * 97 + window * 43;
        const burstStart = .3 + noise(seed + 1) * .9;
        const burstAge = clock % 1.7 - burstStart;
        const glitch = !motion.matches && moving && noise(seed) < .5 && burstAge >= 0 && burstAge < .42;
        if (glitch) {
          const frameSeed = seed + Math.floor(burstAge * 16) * 131;
          const corrupted = ':' + [...port.slice(1)].map((digit, position) =>
            String((Number(digit) + 1 + Math.floor(noise(frameSeed + position * 17) * 9)) % 10),
          ).join('');
          const labelWidth = ctx.measureText(corrupted).width;
          const strength = Math.min(.6, alpha * 1.7);
          // Broken horizontal slices shift independently, like a damaged display.
          for (let slice = 0; slice < 4; slice++) {
            const shift = (noise(frameSeed + slice * 23) - .5) * 16;
            ctx.save();
            ctx.beginPath();
            ctx.rect(p.x - labelWidth / 2 - 12, p.y - 27 + slice * 5, labelWidth + 24, 5);
            ctx.clip();
            ctx.fillStyle = '#ff2e7e'; ctx.globalAlpha = strength * .7;
            ctx.fillText(corrupted, p.x + shift + 4, p.y - 13);
            ctx.fillStyle = '#19e3ff'; ctx.globalAlpha = strength;
            ctx.fillText(corrupted, p.x + shift - 2, p.y - 13);
            ctx.restore();
          }
          // Local static stays confined to the label rather than flashing the page.
          for (let speck = 0; speck < 22; speck++) {
            const n = frameSeed + speck * 31;
            ctx.fillStyle = speck % 3 === 0 ? '#ff2e7e' : '#19e3ff';
            ctx.globalAlpha = strength * (.3 + noise(n + 3) * .5);
            ctx.fillRect(
              p.x + (noise(n) - .5) * (labelWidth + 24),
              p.y - 28 + noise(n + 1) * 23,
              2 + noise(n + 2) * 10, speck % 4 === 0 ? 2 : 1,
            );
          }
          ctx.fillStyle = color;
        } else {
          ctx.fillText(port, p.x, p.y - 13);
        }
        // A centered equalizer travels with the label, with no head or tapered tail.
        // Discrete signal targets blend briefly instead of jumping between frames.
        const bars = 9 + ((i * 7 + cycle * 3) % 5) * 4;
        const spacing = width < 600 ? 3 : 4;
        const waveWidth = (bars - 1) * spacing;
        for (let bar = 0; bar < bars; bar++) {
          const signalClock = clock * 3;
          const tick = Math.floor(signalClock);
          const previous = (bar * 7 + tick * 3 + i) % 5;
          const next = (bar * 7 + (tick + 1) * 3 + i) % 5;
          const level = previous + (next - previous) * smooth((signalClock - tick) / .6);
          const barHeight = 2 + level * 2;
          ctx.globalAlpha = alpha * (.65 + level * .08);
          ctx.fillRect(p.x - waveWidth / 2 + bar * spacing - 1, p.y - barHeight / 2, 2, barHeight);
        }
        // Compact status marks make the deliberate pauses read as queuing.
        const queued = age < 1 || (age >= 3 && age < 3.75) || (age >= 6.5 && age < 7.5);
        ctx.globalAlpha = alpha * .7;
        ctx.fillRect(p.x - 3, p.y + 10, queued ? 6 : 14, 2);
      }
      ctx.restore();
    }
  }

  function draw() {
    ctx.clearRect(0, 0, width, height);
    const rail = Math.min(width * .18, 245);
    // Two asymmetric banks of hardware frame the copy instead of crossing it.
    for (let side = 0; side < 2; side++) {
      ctx.save();
      ctx.translate(side ? width : 0, 0);
      ctx.scale(side ? -1 : 1, 1);
      const drift = cameraX * (side ? -.15 : .15);
      ctx.translate(drift, cameraY * .18);
      for (let panel = 0; panel < 5; panel++) {
        const y = panel * height / 4 - 100 + side * 85;
        const depth = rail * (.65 + (panel % 3) * .13);
        const color = colors[(panel + side * 2) % colors.length];
        ctx.beginPath();
        ctx.moveTo(-20, y); ctx.lineTo(depth - 42, y);
        ctx.lineTo(depth, y + 42); ctx.lineTo(depth, y + 145);
        ctx.lineTo(depth - 24, y + 169); ctx.lineTo(-20, y + 169); ctx.closePath();
        ctx.fillStyle = '#0b1020'; ctx.globalAlpha = .65; ctx.fill();
        ctx.strokeStyle = color; ctx.lineWidth = 1; ctx.globalAlpha = .18; ctx.stroke();
        // A bright chamfer, with a second offset edge like split neon signage.
        ctx.beginPath(); ctx.moveTo(depth - 42, y); ctx.lineTo(depth, y + 42); ctx.lineTo(depth, y + 83);
        ctx.globalAlpha = .45; ctx.shadowColor = color; ctx.shadowBlur = 13; ctx.stroke();
        ctx.shadowBlur = 0;
        ctx.beginPath(); ctx.moveTo(depth - 47, y + 8); ctx.lineTo(depth - 8, y + 47);
        ctx.strokeStyle = '#ff2e7e'; ctx.globalAlpha = .22; ctx.stroke();
        // Fine routed circuitry, with a luminous scan traveling along each trace.
        for (let trace = 0; trace < 3; trace++) {
          const route = new Path2D();
          const offset = trace * 8;
          route.moveTo(0, y + 97 + offset); route.lineTo(depth * .4, y + 97 + offset);
          route.lineTo(depth * .4 + 22, y + 119 + offset); route.lineTo(depth - 24, y + 119 + offset);
          ctx.strokeStyle = color; ctx.globalAlpha = .17; ctx.stroke(route);
          ctx.setLineDash([18, 260]); ctx.lineDashOffset = -time * 23 - panel * 53 - trace * 18;
          ctx.globalAlpha = .65; ctx.stroke(route); ctx.setLineDash([]);
        }
        // Slow, smooth activity bars avoid flashing or random glitch noise.
        for (let bar = 0; bar < 9; bar++) {
          ctx.fillStyle = color;
          ctx.globalAlpha = .1 + .18 * (1 + Math.sin(time * .65 + bar * .8 + panel)) / 2;
          ctx.fillRect(12 + bar * 7, y + 147, 3, -5 - ((bar * 13 + panel * 7) % 18));
        }
      }
      ctx.restore();
    }
    // Port numbers slowly materialize on the boards, linger, then dissolve.
    for (let i = 0; i < 6; i++) {
      const clock = time + i * 2.3;
      const cycle = Math.floor(clock / 15);
      const age = clock % 15;
      const opacity = smooth(age / 2) * (1 - smooth((age - 6) / 3));
      const right = i % 2 === 1;
      const x = right ? width - rail * .5 : rail * .5;
      const y = height * (.22 + Math.floor(i / 2) * .28) + cameraY * .18;
      ctx.save();
      ctx.textAlign = 'center';
      ctx.font = `${Math.max(12, Math.min(24, rail * .12))}px "Cascadia Mono", Consolas, monospace`;
      ctx.fillStyle = colors[i % colors.length];
      ctx.globalAlpha = opacity * .45;
      ctx.fillText(':' + ports[(i + cycle) % ports.length], x, y);
      ctx.restore();
    }
    drawTransfers(rail);
    // Tiny port readouts anchor the atmosphere to Port Why rather than a generic grid.
    if (width > 900) {
      ctx.font = '10px "Cascadia Mono", Consolas, monospace';
      const labels = ['TCP // :3000', 'PID / 22916', 'WSL :: RELAY', '127.0.0.1', 'PORT / :5173'];
      for (let i = 0; i < labels.length; i++) {
        const x = i % 2 ? width - rail + 25 : 25;
        const y = 215 + i * (height - 220) / labels.length;
        ctx.globalAlpha = .32; ctx.fillStyle = colors[i % 3];
        ctx.fillText(labels[i], x, y);
        ctx.globalAlpha = .15;
        ctx.fillRect(x, y + 12, 52, 1); ctx.fillRect(x + 58, y + 12, 12, 3);
      }
    }
    ctx.globalAlpha = 1;
  }
  function tick(now: number) {
    time += Math.min((now - last) / 1000, .05);
    last = now;
    cameraX += (pointerX - cameraX) * .035;
    cameraY += (pointerY - cameraY) * .035;
    draw();
    frame = requestAnimationFrame(tick);
  }
  function restart() {
    cancelAnimationFrame(frame);
    if (disposed) return;
    if (motion.matches) { cameraX = cameraY = 0; draw(); }
    else if (!document.hidden) { last = performance.now(); frame = requestAnimationFrame(tick); }
  }
  function resize() {
    width = canvas.clientWidth; height = canvas.clientHeight;
    const ratio = Math.min(devicePixelRatio || 1, 2);
    canvas.width = Math.round(width * ratio); canvas.height = Math.round(height * ratio);
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    draw();
  }
  function pointer(event: PointerEvent) {
    if (motion.matches || event.pointerType !== 'mouse') return;
    pointerX = (event.clientX / width - .5) * 65;
    pointerY = (event.clientY / height - .5) * 25;
  }
  function scroll() { if (!motion.matches) pointerY = Math.min(window.scrollY * .06, 70); }
  const observer = new ResizeObserver(resize);
  observer.observe(canvas);
  document.addEventListener('visibilitychange', restart);
  motion.addEventListener('change', restart);
  window.addEventListener('pointermove', pointer, { passive: true });
  window.addEventListener('scroll', scroll, { passive: true });
  function dispose() {
    disposed = true; cancelAnimationFrame(frame); observer.disconnect();
    document.removeEventListener('visibilitychange', restart);
    motion.removeEventListener('change', restart);
    window.removeEventListener('pointermove', pointer);
    window.removeEventListener('scroll', scroll);
    document.removeEventListener('astro:before-swap', dispose);
    window.removeEventListener('pagehide', onPageHide);
    window.removeEventListener('pageshow', onPageShow);
  }
  function onPageHide(event: PageTransitionEvent) {
    if (event.persisted) cancelAnimationFrame(frame); else dispose();
  }
  function onPageShow(event: PageTransitionEvent) { if (event.persisted) restart(); }
  document.addEventListener('astro:before-swap', dispose, { once: true });
  window.addEventListener('pagehide', onPageHide);
  window.addEventListener('pageshow', onPageShow);
  resize(); restart();
}
