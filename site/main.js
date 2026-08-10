"use strict";
// NotificationNanny landing page — no framework, no bundler.
// Compiled with plain `tsc` (see package.json) into ../main.js and loaded
// via a single <script src="main.js" defer> tag.
const REPO = "chessper53/NotificationNanny";
const CACHE_KEY = "nn-site-stats-v1";
const CACHE_TTL_MS = 60 * 60 * 1000; // 1h — plenty fresh for marketing numbers, keeps us well under the unauthenticated GitHub API rate limit.
// ---------------------------------------------------------------------------
// Number formatting — compact, matches the stat-tile "auto-compact" contract.
// ---------------------------------------------------------------------------
const compactFormatter = new Intl.NumberFormat("en", { notation: "compact", maximumFractionDigits: 1 });
function formatCompact(n) {
    return compactFormatter.format(n);
}
// ---------------------------------------------------------------------------
// Stats: fetch from GitHub, cache in localStorage, render into the tiles.
// Falls back to whatever's cached (even if stale) on network/rate-limit
// failure, then to an em dash if there's truly nothing to show.
// ---------------------------------------------------------------------------
function readCache() {
    try {
        const raw = localStorage.getItem(CACHE_KEY);
        if (!raw)
            return null;
        return JSON.parse(raw);
    }
    catch {
        return null;
    }
}
function writeCache(stats) {
    try {
        localStorage.setItem(CACHE_KEY, JSON.stringify(stats));
    }
    catch {
        // Storage can be unavailable (private browsing, quota) — the page still
        // works, it just re-fetches next visit instead of reading a cache.
    }
}
async function fetchLiveStats() {
    const [repoRes, releasesRes] = await Promise.all([
        fetch(`https://api.github.com/repos/${REPO}`),
        fetch(`https://api.github.com/repos/${REPO}/releases?per_page=100`),
    ]);
    if (!repoRes.ok || !releasesRes.ok) {
        throw new Error(`GitHub API responded ${repoRes.status}/${releasesRes.status}`);
    }
    const repo = await repoRes.json();
    const releases = await releasesRes.json();
    const downloads = releases.reduce((sum, release) => sum + release.assets.reduce((s, a) => s + (a.download_count ?? 0), 0), 0);
    return {
        stars: repo.stargazers_count ?? 0,
        forks: repo.forks_count ?? 0,
        downloads,
        latestTag: releases[0]?.tag_name ?? null,
        fetchedAt: Date.now(),
    };
}
function prefersReducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}
function easeOutCubic(t) {
    return 1 - Math.pow(1 - t, 3);
}
function animateCountUp(el, to, duration = 1200) {
    const start = performance.now();
    function tick(now) {
        const progress = Math.min(1, (now - start) / duration);
        const value = Math.round(to * easeOutCubic(progress));
        el.textContent = formatCompact(value);
        if (progress < 1) {
            requestAnimationFrame(tick);
        }
    }
    requestAnimationFrame(tick);
}
const animatedStats = new Set();
function renderStats(stats) {
    const numericTiles = {
        downloads: stats.downloads,
        stars: stats.stars,
        forks: stats.forks,
    };
    for (const [key, value] of Object.entries(numericTiles)) {
        const el = document.querySelector(`[data-stat="${key}"] [data-value]`);
        if (!el)
            continue;
        el.classList.remove("is-loading");
        if (prefersReducedMotion() || animatedStats.has(key)) {
            el.textContent = formatCompact(value);
        }
        else {
            animatedStats.add(key);
            animateCountUp(el, value);
        }
    }
    const versionEl = document.querySelector('[data-stat="version"] [data-value]');
    if (versionEl) {
        versionEl.textContent = stats.latestTag ?? "—";
        versionEl.classList.remove("is-loading");
    }
}
async function loadStats() {
    const cached = readCache();
    if (cached) {
        renderStats(cached);
    }
    const isFresh = cached && Date.now() - cached.fetchedAt < CACHE_TTL_MS;
    if (isFresh)
        return;
    try {
        const fresh = await fetchLiveStats();
        writeCache(fresh);
        renderStats(fresh);
    }
    catch {
        // Rate-limited or offline: keep showing the cached numbers (already
        // rendered above) rather than blanking the tiles back to an em dash.
    }
}
// ---------------------------------------------------------------------------
// Copy-to-clipboard for the install commands.
// ---------------------------------------------------------------------------
function textOf(id) {
    return document.getElementById(id)?.textContent?.trim() ?? "";
}
async function copyToClipboard(text) {
    try {
        await navigator.clipboard.writeText(text);
        return true;
    }
    catch {
        return false;
    }
}
function flashCopied(button) {
    const label = button.querySelector(".copy-label");
    const original = label?.textContent ?? "Copy";
    button.classList.add("copied");
    if (label)
        label.textContent = "Copied";
    window.setTimeout(() => {
        button.classList.remove("copied");
        if (label)
            label.textContent = original;
    }, 1600);
}
function setupCopyButtons() {
    document.querySelectorAll("[data-copy]").forEach((button) => {
        button.addEventListener("click", async () => {
            const targetId = button.getAttribute("data-copy");
            if (!targetId)
                return;
            if (await copyToClipboard(textOf(targetId)))
                flashCopied(button);
        });
    });
    document.querySelectorAll("[data-copy-multi]").forEach((button) => {
        button.addEventListener("click", async () => {
            const ids = (button.getAttribute("data-copy-multi") ?? "").split(",").map((s) => s.trim()).filter(Boolean);
            const text = ids.map(textOf).join("\n");
            if (await copyToClipboard(text))
                flashCopied(button);
        });
    });
}
// ---------------------------------------------------------------------------
// Reveal-on-scroll — small, single-fire, respects prefers-reduced-motion via
// the CSS transition-duration override (see styles.css).
// ---------------------------------------------------------------------------
function setupReveal() {
    const targets = document.querySelectorAll("[data-reveal]");
    if (!("IntersectionObserver" in window) || targets.length === 0) {
        targets.forEach((el) => el.classList.add("is-visible"));
        return;
    }
    const observer = new IntersectionObserver((entries) => {
        for (const entry of entries) {
            if (!entry.isIntersecting)
                continue;
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
        }
    }, { threshold: 0.15, rootMargin: "0px 0px -40px 0px" });
    targets.forEach((el) => observer.observe(el));
}
// ---------------------------------------------------------------------------
// Screenshot skeletons — the shimmering placeholder (see .shot in styles.css)
// stays up until each lazy-loaded screenshot actually decodes, then fades in.
// ---------------------------------------------------------------------------
function setupScreenshotSkeletons() {
    document.querySelectorAll(".shot img").forEach((img) => {
        const reveal = () => img.closest(".shot")?.classList.add("is-loaded");
        if (img.complete) {
            reveal();
        }
        else {
            img.addEventListener("load", reveal, { once: true });
            img.addEventListener("error", reveal, { once: true });
        }
    });
}
// ---------------------------------------------------------------------------
document.addEventListener("DOMContentLoaded", () => {
    setupCopyButtons();
    setupReveal();
    setupScreenshotSkeletons();
    void loadStats();
});
