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
  const smooth = (value: number) => {
    const t = Math.max(0, Math.min(1, value));
    return t * t * (3 - 2 * t);
  };

  function drawTransfers(rail: number) {
    // Staggered transmissions: both directions, some delivered, some fragmented.
    const count = width < 600 ? 12 : 26;
    for (let i = 0; i < count; i++) {
      const clock = time + i * 1.618;
      const cycle = Math.floor(clock / 19);
      const age = clock % 19;
      if (age > 13) continue;
      const direction = (i + cycle) % 2 ? -1 : 1;
      const progress = Math.min(age / 11, 1);
      const start = rail * .7;
      const distance = width - start * 2;
      const point = (t: number) => ({
        x: direction > 0 ? start + distance * t : width - start - distance * t,
        y: height * (.12 + ((i * 7) % count) / (count - 1) * .8) + cameraY * .12
          + smooth((t - .33) / .12) * 30 - smooth((t - .66) / .12) * 30,
      });
      const breaks = (i + cycle) % 3 === 1;
      const breakAt = .38 + (i % 3) * .12;
      const shattered = breaks && progress >= breakAt;
      const p = point(shattered ? breakAt : progress);
      const color = colors[(i + cycle) % colors.length];
      const port = ':' + ports[(i * 3 + cycle) % ports.length];
      const envelope = smooth(age / 1.4) * (1 - smooth((age - 10.5) / 2.5));
      // Low contrast through the reading column, stronger as signals approach hardware.
      const edge = Math.abs(p.x / width - .5) * 2;
      const alpha = envelope * (.16 + .3 * edge * edge);
      ctx.save();
      ctx.fillStyle = ctx.strokeStyle = color;
      ctx.font = `${width < 600 ? 11 : 14}px "Cascadia Mono", Consolas, monospace`;
      if (shattered) {
        const elapsed = age - breakAt * 11;
        if (elapsed < 2.8) {
          // Deterministic debris: no random per-frame noise, flash, or screen shake.
          const fade = 1 - smooth(elapsed / 2.8);
          for (let pixel = 0; pixel < 24; pixel++) {
            const angle = pixel * 2.39996 + i;
            const speed = 14 + (pixel * 17 % 47);
            const travel = elapsed * speed;
            const x = p.x + (pixel % 8 - 4) * 5 + Math.cos(angle) * travel + direction * elapsed * 15;
            const y = p.y + (Math.floor(pixel / 8) - 1) * 5 + Math.sin(angle) * travel + elapsed * elapsed * 5;
            ctx.globalAlpha = alpha * fade * (.5 + pixel % 3 * .25);
            const size = pixel % 4 === 0 ? 3 : 2;
            ctx.fillRect(x, y, size, size);
          }
        }
      } else {
        ctx.globalAlpha = alpha;
        ctx.fillText(port, p.x - 20, p.y - 7);
        // Broken horizontal fragments trail behind the port identifier.
        for (let bit = 0; bit < 6; bit++) {
          const tail = point(Math.max(0, progress - bit * .012));
          ctx.globalAlpha = alpha * (1 - bit / 6);
          ctx.fillRect(tail.x, tail.y + bit % 2 * 3, -direction * (bit % 2 ? 5 : 12), 1);
        }
        ctx.globalAlpha = alpha * .7;
        ctx.strokeRect(p.x - 25, p.y - 21, 6, 6);
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
