"use strict";
// NotificationNanny landing page — no framework, no bundler.
// Compiled with plain `tsc` (see package.json) into ../main.js and loaded
// via a single <script src="main.js" defer> tag.
const REPO = "chessper53/NotificationNanny";
const CACHE_KEY = "nn-site-stats-v2";
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
        downloads,
        latestTag: releases[0]?.tag_name ?? null,
        fetchedAt: Date.now(),
    };
}
function renderStats(stats) {
    const numericTiles = {
        downloads: stats.downloads,
        stars: stats.stars,
    };
    for (const [key, value] of Object.entries(numericTiles)) {
        const el = document.querySelector(`[data-stat="${key}"] [data-value]`);
        if (!el)
            continue;
        el.textContent = formatCompact(value);
        el.classList.remove("is-loading");
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
// Features showcase: one tab per settings tab, following the WAI-ARIA tabs
// pattern (roving tabindex, arrow keys, Home/End, selection follows focus).
// The markup ships with the tab list hidden and every panel visible, so
// without JS the page still shows all screenshots, stacked.
// ---------------------------------------------------------------------------
function setupShowcase() {
    const root = document.querySelector("[data-showcase]");
    const tablist = root?.querySelector('[role="tablist"]');
    if (!root || !tablist)
        return;
    const tabs = Array.from(tablist.querySelectorAll('[role="tab"]'));
    if (tabs.length === 0)
        return;
    function select(next, moveFocus) {
        for (const tab of tabs) {
            const isSelected = tab === next;
            tab.setAttribute("aria-selected", String(isSelected));
            tab.tabIndex = isSelected ? 0 : -1;
            const panel = document.getElementById(tab.getAttribute("aria-controls") ?? "");
            if (panel)
                panel.hidden = !isSelected;
        }
        if (moveFocus)
            next.focus();
        // On narrow screens the tab list scrolls sideways; keep the selection in view.
        next.scrollIntoView({ block: "nearest", inline: "nearest" });
    }
    tabs.forEach((tab, index) => {
        tab.addEventListener("click", () => select(tab, false));
        tab.addEventListener("keydown", (event) => {
            let target;
            switch (event.key) {
                case "ArrowDown":
                case "ArrowRight":
                    target = (index + 1) % tabs.length;
                    break;
                case "ArrowUp":
                case "ArrowLeft":
                    target = (index - 1 + tabs.length) % tabs.length;
                    break;
                case "Home":
                    target = 0;
                    break;
                case "End":
                    target = tabs.length - 1;
                    break;
                default:
                    return;
            }
            const next = tabs[target];
            if (!next)
                return;
            event.preventDefault();
            select(next, true);
        });
    });
    const initial = tabs.find((tab) => tab.getAttribute("aria-selected") === "true") ?? tabs[0];
    for (const tab of tabs) {
        const panel = document.getElementById(tab.getAttribute("aria-controls") ?? "");
        if (panel)
            panel.hidden = tab !== initial;
    }
    tablist.hidden = false;
    root.classList.add("is-enhanced");
}
// ---------------------------------------------------------------------------
document.addEventListener("DOMContentLoaded", () => {
    setupCopyButtons();
    setupShowcase();
    void loadStats();
});
