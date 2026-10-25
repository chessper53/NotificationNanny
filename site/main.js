"use strict";
// NotificationNanny landing page. No framework, no bundler: plain `tsc`
// compiles this into ../main.js, which index.html loads with defer.
const REPO = "chessper53/NotificationNanny";
const CACHE_KEY = "nn-site-stats-v3";
// An hour is fresh enough and keeps well under the unauthenticated API limit.
const CACHE_TTL_MS = 60 * 60 * 1000;
// Downloads, stars and the latest version under the hero. The row stays
// hidden if GitHub can't be reached and nothing is cached, rather than
// showing placeholders.
function readCache() {
    try {
        const raw = localStorage.getItem(CACHE_KEY);
        return raw ? JSON.parse(raw) : null;
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
        // Private browsing or full storage: fetch again next visit.
    }
}
async function fetchStats() {
    const [repoRes, releasesRes] = await Promise.all([
        fetch(`https://api.github.com/repos/${REPO}`),
        fetch(`https://api.github.com/repos/${REPO}/releases?per_page=100`),
    ]);
    if (!repoRes.ok || !releasesRes.ok) {
        throw new Error(`GitHub API responded ${repoRes.status}/${releasesRes.status}`);
    }
    const repo = await repoRes.json();
    const releases = await releasesRes.json();
    const downloads = releases.reduce((sum, r) => sum + r.assets.reduce((s, a) => s + (a.download_count ?? 0), 0), 0);
    const tag = releases[0]?.tag_name;
    if (!tag)
        throw new Error("No releases");
    return { tag, downloads, stars: repo.stargazers_count ?? 0, fetchedAt: Date.now() };
}
const compact = new Intl.NumberFormat("en", { notation: "compact", maximumFractionDigits: 1 });
function renderStats(stats) {
    const row = document.getElementById("stats");
    if (!row)
        return;
    const values = {
        downloads: compact.format(stats.downloads),
        stars: compact.format(stats.stars),
        version: stats.tag.replace(/^v/, ""),
    };
    for (const [key, value] of Object.entries(values)) {
        const el = row.querySelector(`[data-stat="${key}"]`);
        if (el)
            el.textContent = value;
    }
    row.hidden = false;
}
async function loadStats() {
    const cached = readCache();
    if (cached)
        renderStats(cached);
    if (cached && Date.now() - cached.fetchedAt < CACHE_TTL_MS)
        return;
    try {
        const fresh = await fetchStats();
        writeCache(fresh);
        renderStats(fresh);
    }
    catch {
        // Offline or rate limited: whatever was cached is already shown.
    }
}
// Copy buttons: data-copy names the element whose text is copied.
function setupCopy() {
    document.querySelectorAll("[data-copy]").forEach((button) => {
        button.addEventListener("click", async () => {
            const source = document.getElementById(button.dataset.copy ?? "");
            if (!source)
                return;
            try {
                await navigator.clipboard.writeText(source.textContent ?? "");
            }
            catch {
                return;
            }
            button.textContent = "Copied";
            button.classList.add("done");
            window.setTimeout(() => {
                button.textContent = "Copy";
                button.classList.remove("done");
            }, 1600);
        });
    });
}
// The demo autoplays on a loop; respect reduced motion by showing the poster
// with controls instead.
function setupDemo() {
    const video = document.querySelector(".demo video");
    if (!video || !window.matchMedia("(prefers-reduced-motion: reduce)").matches)
        return;
    video.removeAttribute("autoplay");
    video.pause();
    video.controls = true;
}
setupDemo();
setupCopy();
void loadStats();
