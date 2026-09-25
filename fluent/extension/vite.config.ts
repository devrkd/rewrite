import { defineConfig } from "vite";
import { resolve } from "path";

/**
 * Vite config for a Manifest V3 Chrome extension.
 *
 * HTML pages live at the project root in popup/ and options/ so that
 * their dist paths match the manifest.json entries exactly.
 * JS entry points (background, content) live in src/ and are output
 * to dist/background/ and dist/content/.
 */
export default defineConfig({
  build: {
    outDir: "dist",
    emptyOutDir: true,
    sourcemap: false,
    minify: false,
    target: "es2022",
    // Disable the modulepreload polyfill — it uses `new Function` which
    // is blocked by the extension's Content Security Policy.
    modulePreload: { polyfill: false },
    rollupOptions: {
      input: {
        // JS-only entry points
        "background/service-worker": resolve(__dirname, "src/background/service-worker.ts"),
        "content/index":             resolve(__dirname, "src/content/index.ts"),
        // HTML pages — placed at root level so dist paths match manifest
        "popup/index":               resolve(__dirname, "popup/index.html"),
        "options/index":             resolve(__dirname, "options/index.html"),
      },
      output: {
        entryFileNames: "[name].js",
        chunkFileNames: "[name].js",
        assetFileNames: "[name].[ext]",
        format: "esm",
        manualChunks: undefined,
      },
    },
  },
  // Copies manifest.json + icons/ → dist/
  publicDir: "public",
});
