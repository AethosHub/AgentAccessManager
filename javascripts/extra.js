/* Interactivity + self-rendered Mermaid for the Architecture Guide.
   Mermaid is vendored locally (javascripts/mermaid.min.js) and rendered here,
   so diagrams work offline with no view-time CDN dependency. Diagrams also get a
   pan/zoom lightbox (no external library). */

function aimTheme() {
  const scheme = document.body.getAttribute("data-md-color-scheme");
  return scheme === "slate" ? "dark" : "default";
}

/* Brand-tinted mermaid theme, mirroring the AethosHub tokens in stylesheets/extra.css
   (blue #2F7CFF on ink #0B0F1A). Built on mermaid's "base" theme, which derives the
   long tail of colours from these anchors. */
function aimMermaidVariables() {
  const shared = { fontFamily: "Poppins, system-ui, sans-serif" };
  if (aimTheme() === "dark") {
    return Object.assign(shared, {
      darkMode: true,
      background: "#0b0f1a",
      textColor: "#f2f6fd",
      primaryColor: "#14243f",
      primaryTextColor: "#f2f6fd",
      primaryBorderColor: "#2f7cff",
      secondaryColor: "#141b28",
      tertiaryColor: "#0f141c",
      lineColor: "#9aa6bb",
      clusterBkg: "#0f141c",
      clusterBorder: "#2b3850",
      edgeLabelBackground: "#0b0f1a",
      noteBkgColor: "#1d2636",
      noteTextColor: "#f2f6fd",
      noteBorderColor: "#2b3850",
      actorBkg: "#14243f",
      actorBorder: "#2f7cff",
      actorTextColor: "#f2f6fd",
    });
  }
  return Object.assign(shared, {
    background: "#ffffff",
    textColor: "#0b0f1a",
    primaryColor: "#e9f1ff",
    primaryTextColor: "#0b0f1a",
    primaryBorderColor: "#2f7cff",
    secondaryColor: "#f3f6fc",
    tertiaryColor: "#ffffff",
    lineColor: "#4c5567",
    clusterBkg: "#f3f6fc",
    clusterBorder: "#d3dcec",
    edgeLabelBackground: "#ffffff",
    noteBkgColor: "#fdf6e3",
    noteTextColor: "#0b0f1a",
    noteBorderColor: "#e4d8b4",
    actorBkg: "#e9f1ff",
    actorBorder: "#2f7cff",
    actorTextColor: "#0b0f1a",
  });
}

async function aimRenderMermaid() {
  if (typeof window.mermaid === "undefined") return;
  const blocks = document.querySelectorAll(".aim-diagram");
  if (!blocks.length) return;

  window.mermaid.initialize({
    startOnLoad: false,
    theme: "base",
    themeVariables: aimMermaidVariables(),
    securityLevel: "loose",
    flowchart: { useMaxWidth: true, htmlLabels: true },
  });

  let i = 0;
  for (const el of blocks) {
    if (!el.dataset.mmdSrc) {
      const code = el.querySelector("code");
      el.dataset.mmdSrc = (code ? code.textContent : el.textContent).trim();
    }
    const src = el.dataset.mmdSrc;
    if (!src) continue;
    try {
      const { svg } = await window.mermaid.render(`__mmd_${i++}_${Date.now()}`, src);
      el.innerHTML = svg;
      el.classList.add("aim-mmd-done");
      const btn = document.createElement("button");
      btn.className = "aim-zoom-btn";
      btn.type = "button";
      btn.title = "Zoom (or double-click the diagram)";
      btn.setAttribute("aria-label", "Zoom diagram");
      btn.textContent = "⤢";
      btn.addEventListener("click", (e) => {
        e.stopPropagation();
        aimOpenZoom(el.querySelector("svg"));
      });
      el.appendChild(btn);
      el.addEventListener("dblclick", () => aimOpenZoom(el.querySelector("svg")));
    } catch (e) {
      el.innerHTML =
        '<div class="admonition failure"><p>Diagram failed to render.</p></div>';
      // eslint-disable-next-line no-console
      console.error("mermaid render error:", e);
    }
  }
}

/* ---- Pan/zoom lightbox (dependency-free) ---- */
let aimZoom = null;

function aimEnsureOverlay() {
  if (aimZoom) return aimZoom;
  const overlay = document.createElement("div");
  overlay.className = "aim-zoom-overlay";
  overlay.innerHTML =
    '<div class="aim-zoom-bar">' +
    '<button data-act="out" title="Zoom out">−</button>' +
    '<button data-act="in" title="Zoom in">+</button>' +
    '<button data-act="reset" title="Fit">⤢</button>' +
    '<button data-act="close" title="Close (Esc)">✕</button>' +
    "</div>" +
    '<div class="aim-zoom-stage"></div>' +
    '<div class="aim-zoom-hint">scroll to zoom · drag to pan · Esc to close</div>';
  document.body.appendChild(overlay);
  const stage = overlay.querySelector(".aim-zoom-stage");
  const state = { s: 1, tx: 0, ty: 0, w: 0, h: 0, svg: null, drag: null };

  const apply = () => {
    if (state.svg) state.svg.style.transform = `translate(${state.tx}px, ${state.ty}px) scale(${state.s})`;
  };
  const fit = () => {
    const vw = stage.clientWidth;
    const vh = stage.clientHeight;
    state.s = Math.min((vw * 0.92) / state.w, (vh * 0.92) / state.h, 4);
    state.tx = (vw - state.w * state.s) / 2;
    state.ty = (vh - state.h * state.s) / 2;
    apply();
  };
  const zoomAt = (factor, cx, cy) => {
    const ns = Math.min(Math.max(state.s * factor, 0.1), 14);
    state.tx = cx - (ns / state.s) * (cx - state.tx);
    state.ty = cy - (ns / state.s) * (cy - state.ty);
    state.s = ns;
    apply();
  };
  const close = () => {
    overlay.classList.remove("open");
    stage.innerHTML = "";
    state.svg = null;
  };

  overlay.querySelector('[data-act="close"]').addEventListener("click", close);
  overlay.querySelector('[data-act="reset"]').addEventListener("click", fit);
  overlay.querySelector('[data-act="in"]').addEventListener("click", () => zoomAt(1.25, stage.clientWidth / 2, stage.clientHeight / 2));
  overlay.querySelector('[data-act="out"]').addEventListener("click", () => zoomAt(0.8, stage.clientWidth / 2, stage.clientHeight / 2));
  overlay.addEventListener("mousedown", (e) => {
    if (e.target.closest(".aim-zoom-bar")) return;
    if (e.target === overlay) return close();
    state.drag = { x: e.clientX - state.tx, y: e.clientY - state.ty };
    stage.classList.add("grabbing");
  });
  window.addEventListener("mousemove", (e) => {
    if (!state.drag) return;
    state.tx = e.clientX - state.drag.x;
    state.ty = e.clientY - state.drag.y;
    apply();
  });
  window.addEventListener("mouseup", () => {
    state.drag = null;
    stage.classList.remove("grabbing");
  });
  stage.addEventListener("wheel", (e) => {
    e.preventDefault();
    const r = stage.getBoundingClientRect();
    zoomAt(e.deltaY < 0 ? 1.12 : 0.89, e.clientX - r.left, e.clientY - r.top);
  }, { passive: false });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && overlay.classList.contains("open")) close();
  });

  aimZoom = { overlay, stage, state, fit };
  return aimZoom;
}

function aimOpenZoom(svg) {
  if (!svg) return;
  const z = aimEnsureOverlay();
  const clone = svg.cloneNode(true);
  const vb = svg.viewBox && svg.viewBox.baseVal;
  z.state.w = vb && vb.width ? vb.width : svg.getBoundingClientRect().width;
  z.state.h = vb && vb.height ? vb.height : svg.getBoundingClientRect().height;
  clone.removeAttribute("style");
  clone.style.width = z.state.w + "px";
  clone.style.height = z.state.h + "px";
  z.stage.innerHTML = "";
  z.stage.appendChild(clone);
  z.state.svg = clone;
  z.overlay.classList.add("open");
  z.fit();
}

function aimInit() {
  const chips = document.querySelectorAll(".aim-chip");
  const mods = document.querySelectorAll(".aim-mod");
  if (chips.length && mods.length) {
    chips.forEach((chip) => {
      chip.addEventListener("click", () => {
        const layer = chip.dataset.layer;
        chips.forEach((c) => c.classList.toggle("active", c === chip));
        mods.forEach((m) => {
          const show = layer === "all" || m.dataset.layer === layer;
          m.classList.toggle("hidden", !show);
        });
      });
    });
  }

  const steps = document.querySelectorAll(".aim-step");
  const panels = document.querySelectorAll(".aim-step-panel");
  if (steps.length && panels.length) {
    const activate = (i) => {
      steps.forEach((s, idx) => s.classList.toggle("active", idx === i));
      panels.forEach((p, idx) => p.classList.toggle("active", idx === i));
    };
    steps.forEach((step, i) => step.addEventListener("click", () => activate(i)));
    activate(0);
  }

  aimRenderMermaid();
}

function aimWatchTheme() {
  let last = aimTheme();
  new MutationObserver(() => {
    const now = aimTheme();
    if (now !== last) {
      last = now;
      aimRenderMermaid();
    }
  }).observe(document.body, { attributes: true, attributeFilter: ["data-md-color-scheme"] });
}

if (typeof document$ !== "undefined" && document$.subscribe) {
  document$.subscribe(() => {
    aimInit();
  });
} else {
  document.addEventListener("DOMContentLoaded", aimInit);
}
document.addEventListener("DOMContentLoaded", aimWatchTheme);
