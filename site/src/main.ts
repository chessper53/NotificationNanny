// No framework or runtime dependencies. tsc emits the tracked ../main.js.
function setupPreview(): void {
  const desktop = document.querySelector<HTMLElement>("#preview-desktop");
  const notification = document.querySelector<HTMLElement>("#preview-notification");
  const scale = document.querySelector<HTMLInputElement>("#preview-scale");
  const output = document.getElementById("scale-value");
  const status = document.getElementById("preview-status");
  if (!desktop || !notification || !scale) return;

  const positions = Array.from(document.querySelectorAll<HTMLButtonElement>(".position-picker button"));
  const colours = Array.from(document.querySelectorAll<HTMLButtonElement>(".colour-picker button"));

  function announce(): void {
    const position = positions.find(button => button.getAttribute("aria-pressed") === "true");
    const colour = colours.find(button => button.getAttribute("aria-pressed") === "true");
    if (status && scale) {
      status.textContent = `${position?.getAttribute("aria-label")} · ${colour?.getAttribute("aria-label")} · ${scale.value}%`;
    }
  }

  // Native buttons keep every option reachable by Tab; arrows also navigate each group.
  function setupGroup(buttons: HTMLButtonElement[], key: "position" | "tint", columns: number): void {
    buttons.forEach((button, index) => {
      button.addEventListener("click", () => {
        if (!desktop) return;
        buttons.forEach(option => option.setAttribute("aria-pressed", String(option === button)));
        desktop.dataset[key] = button.dataset[key];
        announce();
      });
      button.addEventListener("keydown", event => {
        const steps: Record<string, number> = {
          ArrowRight: 1, ArrowLeft: -1, ArrowDown: columns, ArrowUp: -columns,
        };
        const step = steps[event.key];
        let nextIndex: number;
        if (event.key === "Home") nextIndex = 0;
        else if (event.key === "End") nextIndex = buttons.length - 1;
        else if (step !== undefined) nextIndex = (index + step + buttons.length) % buttons.length;
        else return;
        event.preventDefault();
        const next = buttons[nextIndex];
        next?.focus();
        next?.click();
      });
    });
  }

  setupGroup(positions, "position", 3);
  setupGroup(colours, "tint", 1);
  scale.addEventListener("input", () => {
    notification.style.setProperty("--notification-scale", String(Number(scale.value) / 100));
    if (output) output.textContent = `${scale.value}%`;
    announce();
  });
  // Keep preview submission on this page without reloading it.
  document.querySelector(".preview-controls")?.addEventListener("submit", event => event.preventDefault());
}

function setupCopy(): void {
  document.querySelectorAll<HTMLButtonElement>("[data-copy]").forEach(button => {
    let resetTimer: number | undefined;
    button.addEventListener("click", async () => {
      const source = document.getElementById(button.dataset.copy ?? "");
      const status = button.closest(".code-block")?.querySelector<HTMLElement>(".copy-status");
      if (!source) return;
      window.clearTimeout(resetTimer);
      try {
        await navigator.clipboard.writeText(source.textContent?.trim() ?? "");
        button.textContent = "Copied ✓";
        if (status) status.textContent = "Both commands copied. Paste them into Terminal.";
      } catch {
        // Keep the command selectable and give actionable feedback if clipboard access is blocked.
        const selection = window.getSelection();
        const range = document.createRange();
        range.selectNodeContents(source);
        selection?.removeAllRanges();
        selection?.addRange(range);
        if (status) status.textContent = "Press ⌘C (or Ctrl+C) to copy the selected commands.";
      }
      resetTimer = window.setTimeout(() => {
        button.textContent = "Copy commands ⧉";
        if (status) status.textContent = "";
      }, 4000);
    });
  });
}

function setupDemo(): void {
  const video = document.querySelector<HTMLVideoElement>(".demo video");
  if (!video) return;
  const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
  // Play only while the real footage is visible. Manual playback always remains available.
  let userControlled = false;
  video.addEventListener("pointerdown", () => { userControlled = true; });
  video.addEventListener("keydown", () => { userControlled = true; });
  const pauseForMotion = (): void => {
    if (motion.matches) video.pause();
  };
  motion.addEventListener("change", pauseForMotion);
  if (!("IntersectionObserver" in window)) return;
  const observer = new IntersectionObserver(entries => {
    const entry = entries[0];
    if (!entry) return;
    if (!entry.isIntersecting) {
      video.pause();
    } else if (!motion.matches && !userControlled) {
      void video.play().catch(() => { /* Native controls handle blocked autoplay. */ });
    }
  }, { threshold: 0.35 });
  observer.observe(video);
}

setupPreview();
setupCopy();
setupDemo();
