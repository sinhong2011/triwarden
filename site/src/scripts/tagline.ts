/* Tagline reveal: as the section crosses the viewport, its words turn from muted to full ink in reading order.
   One rAF-throttled scroll listener, attached only while the section is near the viewport. Words stay lit once
   reached. Reduced motion shows every word at full ink straight away (CSS). */
import { reduce, $, $$ } from "./motion";

const root = $("[data-tagline]");
if (root && !reduce) {
  const words = $$(".tagline__word", root);
  let lit = 0, frame = 0;
  const update = () => {
    frame = 0;
    const r = root.getBoundingClientRect(), vh = innerHeight;
    // 0 when the section's top reaches 85% of the viewport, 1 when its bottom passes 45%.
    const p = (vh * 0.85 - r.top) / (r.height + vh * 0.4);
    const n = Math.max(lit, Math.min(words.length, Math.floor(p * (words.length + 1))));
    for (let i = lit; i < n; i++) words[i].classList.add("is-lit");
    lit = n;
    if (lit === words.length) { removeEventListener("scroll", onScroll); io.disconnect(); }
  };
  const onScroll = () => { if (!frame) frame = requestAnimationFrame(update); };
  const io = new IntersectionObserver(([e]) => {
    if (e.isIntersecting) { addEventListener("scroll", onScroll, { passive: true }); onScroll(); }
    else removeEventListener("scroll", onScroll);
  }, { rootMargin: "100px 0px" });
  root.classList.add("is-armed");
  io.observe(root);
}
