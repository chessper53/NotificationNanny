# Local website preview

From this checkout:

```sh
cd site
npm ci
npm run build
npm run serve
```

Open http://127.0.0.1:4186/. This serves only on the local loopback interface.
If the port is occupied, use another port with `python3 -m http.server PORT --bind 127.0.0.1`.

Edit `index.html`, `styles.css`, and `src/main.ts`. Run `npm run build` after
TypeScript changes, or keep `npm run watch` running in another terminal.
The generated `main.js` is tracked because GitHub Pages serves the static files.

The redesign uses a warm neutral background, the product's orange accent,
a feature showcase above the real app footage, followed by FAQs and installation.
The interactive desktop preview is commented out at the bottom of the HTML
for a possible later return. Its controls affect the page only.

Position and colour controls support Tab, arrow keys, Home, and End. The scale
slider is a native range input. The video respects reduced motion and pauses
offscreen. FAQs use native disclosures; commands remain selectable if
clipboard access is unavailable. The page makes no third-party requests.

These commands only preview locally. Production is served by the existing
GitHub Pages workflow after changes to site/ are merged into main.
