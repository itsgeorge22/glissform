import { useLayoutEffect, useRef } from "react";
import type { CSSProperties } from "react";
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { createMacBookWebGL } from "./macBookWebGL";
import MacBookKeyboard from "./MacBookKeyboard";
import MacBookShell, { macBookGeometry } from "./MacBookShell";

gsap.registerPlugin(ScrollTrigger);

export default function SeamlessCloseSection() {
  const sectionRef = useRef<HTMLElement>(null);
  const sceneRef = useRef<HTMLDivElement>(null);
  const trackRef = useRef<HTMLDivElement>(null);
  const deviceRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useLayoutEffect(() => {
    const scene = sceneRef.current!;
    const track = trackRef.current!;
    const device = deviceRef.current!;
    const canvas = canvasRef.current!;
    const revealText = device.querySelector<HTMLElement>(
      ".seamless-macbook__reveal",
    )!;
    const media = gsap.matchMedia();
    let renderer: Awaited<ReturnType<typeof createMacBookWebGL>> = null;
    let disposed = false;
    const pose = { fold: 0 };
    let benchmarkFreezeWallpaper = false;
    const scrollDistance = () => Math.max(800, window.innerHeight * 1.35);
    const sceneTop = () => (window.innerHeight - scene.offsetHeight) / 2 + 36;
    const syncSceneLayout = () => {
      if (!track.classList.contains("seamless-section__track--animated"))
        return;
      track.style.height = `${scene.offsetHeight + scrollDistance()}px`;
      track.style.setProperty("--scene-top", `${sceneTop()}px`);
    };
    const render = () => {
      const closure = pose.fold / 90;
      const reveal = Math.max(0, Math.min(1, (closure - 0.25) / 0.45));
      revealText.style.opacity = String(reveal * reveal * (3 - 2 * reveal));
      renderer?.render(pose.fold, benchmarkFreezeWallpaper);
    };
    const resize = () => {
      device.style.setProperty(
        "--macbook-scale",
        String(device.clientWidth / 900),
      );
      renderer?.resize(device.clientWidth, window.devicePixelRatio);
      syncSceneLayout();
      render();
    };
    const observer = new ResizeObserver(resize);
    observer.observe(device);
    observer.observe(scene);
    resize();

    const image = new Image();
    image.onload = () => {
      if (disposed) return;
      media.add(
        "(min-width: 1156px) and (prefers-reduced-motion: no-preference)",
        () => {
          let active = true;
          const controller = new AbortController();
          let timeline: gsap.core.Timeline | undefined;
          let removeBenchmark: (() => void) | undefined;
          void createMacBookWebGL(
            canvas,
            device,
            image,
            controller.signal,
          ).then((nextRenderer) => {
            if (!active || disposed) {
              nextRenderer?.dispose();
              return;
            }
            renderer = nextRenderer;
            if (!renderer) return;
            renderer.resize(device.clientWidth, window.devicePixelRatio);
            render();
            device.classList.add(
              "seamless-macbook--animated",
              "seamless-macbook--webgl",
            );
            track.classList.add("seamless-section__track--animated");
            syncSceneLayout();
            timeline = gsap.timeline({
              scrollTrigger: {
                trigger: track,
                start: () => `top top+=${sceneTop()}`,
                end: () => `+=${scrollDistance()}`,
                // Native sticky positioning follows Safari's scrolling thread;
                // JS only controls the pose, not the scene's viewport position.
                onRefreshInit: syncSceneLayout,
                scrub: 0.4,
                invalidateOnRefresh: true,
              },
              onUpdate: render,
            });
            // One monotonic gesture: down closes the physical lid; up reopens it.
            // The eased final degrees bring the lid gently onto the base.
            timeline.to(pose, {
              fold: 90,
              duration: 1,
              ease: "power1.inOut",
            });
            if (
              import.meta.env.DEV &&
              new URLSearchParams(location.search).has("motion-benchmark")
            ) {
              void import("./seamlessBenchmark").then(({ attachBenchmark }) => {
                if (!active) return;
                removeBenchmark = attachBenchmark(
                  timeline!.scrollTrigger!,
                  (frozen) => {
                    benchmarkFreezeWallpaper = frozen;
                    render();
                  },
                  () =>
                    canvas
                      .getContext("webgl2")
                      ?.getExtension("WEBGL_lose_context")
                      ?.loseContext(),
                );
              });
            }
            // Local fonts can settle after mount and change the sticky start offset.
            void document.fonts.ready.then(() => {
              if (!disposed) ScrollTrigger.refresh();
            });
          });
          return () => {
            active = false;
            controller.abort();
            timeline?.revert();
            removeBenchmark?.();
            device.classList.remove(
              "seamless-macbook--animated",
              "seamless-macbook--webgl",
            );
            track.classList.remove("seamless-section__track--animated");
            track.style.removeProperty("height");
            track.style.removeProperty("--scene-top");
            renderer?.dispose();
            renderer = null;
            pose.fold = 0;
            render();
          };
        },
      );
    };
    const handleContextLoss = (event: Event) => {
      event.preventDefault();
      media.revert();
    };
    canvas.addEventListener("webglcontextlost", handleContextLoss);
    image.src = "/assets/seamless-desktop.png";

    return () => {
      disposed = true;
      image.onload = null;
      observer.disconnect();
      media.revert();
      canvas.removeEventListener("webglcontextlost", handleContextLoss);
      device.style.removeProperty("--macbook-scale");
    };
  }, []);

  return (
    <section
      className="seamless-section shell"
      id="seamless-close"
      aria-labelledby="seamless-title"
      ref={sectionRef}
    >
      <div className="section-intro seamless-section__intro">
        <h2 id="seamless-title">
          Your Lid Moves.
          <br />
          Your Desktop Stays.
        </h2>
        <p>
          As you close the lid, perspective, blur and shadow follow its
          movement,
          <br />
          making your desktop appear to stay in place.
        </p>
      </div>
      <div className="seamless-section__track" ref={trackRef}>
        <div className="seamless-section__scene" ref={sceneRef}>
          <div
            className="seamless-macbook"
            ref={deviceRef}
            style={
              {
                "--hardware-width": `${macBookGeometry.width}px`,
                "--hardware-depth": `${macBookGeometry.depth}px`,
                "--hardware-radius": `${macBookGeometry.radius}px`,
              } as CSSProperties
            }
            role="img"
            aria-label="Seamless Close preview: scroll down to close the MacBook lid as the desktop changes perspective, blur and shadow, revealing ‘A Little Magic. Every Time You Close.’ Scroll up to reopen it."
          >
            <div className="seamless-macbook__drawing" aria-hidden="true">
              <p className="seamless-macbook__reveal">
                A Little Magic.
                <br />
                <span>Every Time You Close.</span>
              </p>
              <canvas className="seamless-macbook__gpu" ref={canvasRef} />
              <div className="seamless-macbook__contact-shadow" />
              <div className="seamless-macbook__camera">
                <div className="seamless-macbook__hardware">
                  <div className="seamless-macbook__deck">
                    <MacBookShell thickness={17} offset={0} bottomRadius={11} />
                    <MacBookKeyboard />
                    <div className="seamless-macbook__trackpad" />
                    <div className="seamless-macbook__hinge" />
                  </div>
                  <div className="seamless-macbook__lid">
                    <MacBookShell thickness={6} offset={-6} />
                    <div className="seamless-macbook__back">
                      <span className="seamless-macbook__lid-mark" />
                    </div>
                    <div className="seamless-macbook__front">
                      <div className="seamless-macbook__bezel" />
                      <div className="seamless-macbook__screen">
                        <img
                          className="seamless-macbook__still"
                          src="/assets/seamless-desktop-folded.png"
                          width="960"
                          height="600"
                          alt=""
                        />
                      </div>
                      <div className="seamless-macbook__notch">
                        <span className="seamless-macbook__lens" />
                      </div>
                    </div>
                  </div>
                  <div className="seamless-macbook__base">
                    <span className="seamless-macbook__opening" />
                  </div>
                </div>
              </div>
            </div>
          </div>
          <p className="seamless-section__footnote">
            Normal system sleep stays enabled. Press Esc to return during the
            effect.
          </p>
        </div>
      </div>
    </section>
  );
}
