// Development-only repeatable scroll benchmark. Never imported by production.
import type { ScrollTrigger } from "gsap/ScrollTrigger";

export function attachBenchmark(
  trigger: ScrollTrigger,
  freezeWallpaper: (frozen: boolean) => void,
  loseContext: () => void,
) {
  const panel = document.createElement("aside");
  panel.style.cssText =
    "position:fixed;bottom:16px;left:16px;z-index:99999;background:white;color:black;padding:16px;font:14px monospace;max-width:540px;border:1px solid #aaa";
  const button = document.createElement("button");
  button.textContent = "Measure MacBook animation";
  const output = document.createElement("p");
  const label = document.createElement("label");
  const checkbox = document.createElement("input");
  checkbox.type = "checkbox";
  checkbox.onchange = () => freezeWallpaper(checkbox.checked);
  label.append(checkbox, " Freeze wallpaper for isolation");
  output.textContent =
    "Ready. Two identical close/open cycles; first cycle warms the layers.";
  panel.append(button, label, output);
  for (const progress of [0, 0.25, 0.5, 0.75, 1]) {
    const poseButton = document.createElement("button");
    poseButton.textContent = `${progress * 100}%`;
    poseButton.onclick = () =>
      window.scrollTo({
        top: trigger.start + (trigger.end - trigger.start) * progress,
        behavior: "instant",
      });
    panel.append(poseButton);
  }
  const fallbackButton = document.createElement("button");
  fallbackButton.textContent = "Test graphics fallback";
  fallbackButton.onclick = loseContext;
  panel.append(fallbackButton);
  document.body.append(panel);
  let frame = 0;
  button.onclick = () => {
    button.disabled = true;
    checkbox.disabled = true;
    const samples: number[] = [];
    let start = 0;
    let previous = 0;
    output.textContent = "Measuring…";
    const tick = (now: number) => {
      if (document.hidden) {
        output.textContent = "Measurement cancelled: keep this tab visible.";
        button.disabled = false;
        checkbox.disabled = false;
        return;
      }
      if (!start) start = now;
      const elapsed = now - start;
      if (elapsed >= 6000 && previous) samples.push(now - previous);
      previous = now;
      const phase = (elapsed % 6000) / 6000;
      const progress = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
      window.scrollTo({
        top: trigger.start + (trigger.end - trigger.start) * progress,
        behavior: "instant",
      });
      if (elapsed < 12000) {
        frame = requestAnimationFrame(tick);
        return;
      }
      samples.sort((a, b) => a - b);
      const percentile = (p: number) =>
        samples[Math.floor((samples.length - 1) * p)].toFixed(1);
      output.textContent = `${samples.length} frames; median ${percentile(0.5)} ms; p95 ${percentile(0.95)} ms; over 25 ms: ${samples.filter((ms) => ms > 25).length}; over 50 ms: ${samples.filter((ms) => ms > 50).length}.`;
      button.disabled = false;
      checkbox.disabled = false;
    };
    frame = requestAnimationFrame(tick);
  };
  return () => {
    cancelAnimationFrame(frame);
    panel.remove();
  };
}
