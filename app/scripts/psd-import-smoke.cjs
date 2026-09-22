const { app, BrowserWindow } = require("electron");
const fs = require("fs");
const path = require("path");

const fixture = path.resolve(__dirname, "../../art/miscAssets/skyBg.psd");
const psdToolsSource = path.resolve(__dirname, "../../src/electron.renderer/misc/PsdTools.hx");

function fail(message) {
  throw new Error("[PSD SMOKE] " + message);
}

async function run() {
  if (!fs.existsSync(fixture))
    fail("Fixture not found: " + fixture);
  if (!fs.existsSync(psdToolsSource))
    fail("PsdTools source not found: " + psdToolsSource);

  const sourceText = fs.readFileSync(psdToolsSource, "utf8");
  if (sourceText.includes('js.Syntax.code("Buffer")'))
    fail("PsdTools must not rely on the renderer-global Buffer object");
  if (!sourceText.includes("require('buffer')"))
    fail("PsdTools must resolve Buffer through require('buffer')");

  const win = new BrowserWindow({
    show: false,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
      sandbox: false,
      offscreen: true,
    },
  });

  try {
    await win.loadURL("data:text/html;charset=utf-8,<html><body></body></html>");

    const result = await win.webContents.executeJavaScript(
      `(() => {
        const fs = require("fs");
        const bufferModule = require("buffer");
        const BufferCtor = bufferModule && bufferModule.Buffer;
        if (!BufferCtor || typeof BufferCtor.from !== "function")
          throw new Error("require('buffer').Buffer.from is unavailable");

        const agPsd = require("ag-psd");
        if (!agPsd || typeof agPsd.readPsd !== "function")
          throw new Error("ag-psd readPsd is unavailable");

        agPsd.initializeCanvas((w, h) => {
          const canvas = document.createElement("canvas");
          canvas.width = w;
          canvas.height = h;
          return canvas;
        });

        const bytes = fs.readFileSync(${JSON.stringify(fixture)});
        const psd = agPsd.readPsd(bytes, {
          skipCompositeImageData: true,
          skipThumbnail: true,
          logMissingFeatures: false,
        });

        if (!psd || !Number.isFinite(psd.width) || !Number.isFinite(psd.height))
          throw new Error("PSD document dimensions were not decoded");
        if (psd.width <= 0 || psd.height <= 0)
          throw new Error("PSD document has invalid dimensions");

        let layerCount = 0;
        let renderable = null;

        function visit(children) {
          if (!Array.isArray(children)) return;
          for (const layer of children) {
            if (!layer) continue;
            layerCount++;
            if (!renderable && !Array.isArray(layer.children) && layer.canvas)
              renderable = layer;
            visit(layer.children);
          }
        }

        visit(psd.children);

        if (layerCount <= 0)
          throw new Error("PSD layer hierarchy is empty");
        if (!renderable)
          throw new Error("PSD fixture has no renderable leaf layer");

        const full = document.createElement("canvas");
        full.width = psd.width;
        full.height = psd.height;
        const ctx = full.getContext("2d");
        if (!ctx)
          throw new Error("Could not create 2D canvas context");

        ctx.clearRect(0, 0, full.width, full.height);
        ctx.globalAlpha = 1;
        ctx.globalCompositeOperation = "source-over";
        ctx.drawImage(renderable.canvas, renderable.left || 0, renderable.top || 0);

        const dataUrl = full.toDataURL("image/png");
        const comma = dataUrl.indexOf(",");
        if (comma < 0)
          throw new Error("Canvas did not produce a PNG data URL");

        const png = BufferCtor.from(dataUrl.slice(comma + 1), "base64");
        if (!png || png.length < 8)
          throw new Error("PNG buffer is empty");

        const expected = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
        for (let i = 0; i < expected.length; i++) {
          if (png[i] !== expected[i])
            throw new Error("Generated output does not have a valid PNG signature");
        }

        const metadata = {
          source: ${JSON.stringify(fixture)},
          documentWidth: psd.width,
          documentHeight: psd.height,
          layerCount,
          selectedLayerName: renderable.name || "(unnamed layer)",
          selectedLayerBounds: {
            left: renderable.left || 0,
            top: renderable.top || 0,
            right: renderable.right || 0,
            bottom: renderable.bottom || 0,
          },
        };

        const serialized = JSON.stringify(metadata);
        const parsed = JSON.parse(serialized);
        if (parsed.layerCount !== layerCount)
          throw new Error("PSD metadata round-trip failed");

        return {
          width: psd.width,
          height: psd.height,
          layerCount,
          selectedLayer: metadata.selectedLayerName,
          pngBytes: png.length,
        };
      })()`,
      true
    );

    console.log(
      "[PSD SMOKE] PASS " +
        JSON.stringify(result)
    );
  } finally {
    if (!win.isDestroyed()) win.destroy();
  }
}

app.whenReady()
  .then(run)
  .then(() => app.quit())
  .catch((err) => {
    console.error(err && err.stack ? err.stack : err);
    app.exit(1);
  });
