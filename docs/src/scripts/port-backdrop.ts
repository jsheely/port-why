/** Perspective-projected circuit field, inspired by tt-git's canvas backdrop.
 * No WebGL dependency: the small scene projects 3D points onto a 2D canvas.
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

  function project(x: number, z: number) {
    const scale = 520 / (z + 520);
    return {
      x: width / 2 + (x + cameraX) * scale,
      y: height * .28 + (height * .8 + cameraY) * scale,
      scale,
    };
  }
  function draw() {
    ctx.clearRect(0, 0, width, height);
    ctx.lineWidth = 1;
    // The grid recedes toward a vanishing point behind the hero.
    ctx.strokeStyle = '#19e3ff';
    ctx.globalAlpha = .12;
    for (let lane = -12; lane <= 12; lane++) {
      const near = project(lane * 180, 0);
      const far = project(lane * 180, 3200);
      ctx.beginPath(); ctx.moveTo(near.x, near.y); ctx.lineTo(far.x, far.y); ctx.stroke();
    }
    for (let row = 0; row < 22; row++) {
      const z = (row * 160 + time * 35) % 3520;
      const left = project(-2160, z), right = project(2160, z);
      ctx.beginPath(); ctx.moveTo(left.x, left.y); ctx.lineTo(right.x, right.y); ctx.stroke();
    }
    // Packets travel along lanes with a short illuminated trail.
    for (let i = 0; i < 24; i++) {
      const lane = ((i * 7) % 25) - 12;
      const z = ((i * 137 - time * (65 + i % 4 * 15)) % 3200 + 3200) % 3200;
      const point = project(lane * 180, z);
      const tail = project(lane * 180, Math.min(z + 180, 3400));
      ctx.strokeStyle = ctx.fillStyle = colors[i % colors.length];
      // Keep the center quiet enough for reading.
      ctx.globalAlpha = Math.abs(point.x - width / 2) < width * .27 ? .12 : .45;
      ctx.lineWidth = Math.max(1, point.scale * 2);
      ctx.beginPath(); ctx.moveTo(tail.x, tail.y); ctx.lineTo(point.x, point.y); ctx.stroke();
      ctx.beginPath(); ctx.arc(point.x, point.y, Math.max(1.2, point.scale * 3), 0, Math.PI * 2); ctx.fill();
    }
    // Tilted radar rings echo the video's port orbit.
    ctx.strokeStyle = '#a573ff';
    ctx.lineWidth = 1;
    for (let i = 0; i < 4; i++) {
      const phase = (time * .07 + i / 4) % 1;
      ctx.globalAlpha = (1 - phase) * .15;
      ctx.beginPath();
      ctx.ellipse(width * .82 + cameraX * .1, height * .42, 80 + phase * 380, 35 + phase * 160, -.35, 0, Math.PI * 2);
      ctx.stroke();
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
