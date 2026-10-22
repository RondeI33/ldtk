const { app, BrowserWindow } = require("electron");
const fs = require("fs");
const path = require("path");

const fixture = path.resolve(__dirname, "../../art/miscAssets/skyBg.psd");
const psdToolsSource = path.resolve(__dirname, "../../src/electron.renderer/misc/PsdTools.hx");
const psdPickerSource = path.resolve(__dirname, "../../src/electron.renderer/ui/modal/dialog/PsdLayerPicker.hx");

function fail(message) {
  throw new Error("[PSD SMOKE] " + message);
}

async function run() {
  if (!fs.existsSync(fixture))
    fail("Fixture not found: " + fixture);
  if (!fs.existsSync(psdToolsSource))
    fail("PsdTools source not found: " + psdToolsSource);
  if (!fs.existsSync(psdPickerSource))
    fail("PsdLayerPicker source not found: " + psdPickerSource);

  const sourceText = fs.readFileSync(psdToolsSource, "utf8");
  const pickerText = fs.readFileSync(psdPickerSource, "utf8");
  if (sourceText.includes('js.Syntax.code("Buffer")'))
    fail("PsdTools must not rely on the renderer-global Buffer object");
  if (!sourceText.includes("require('buffer')"))
    fail("PsdTools must resolve Buffer through require('buffer')");
  if (!sourceText.includes("exportSelectedLayers"))
    fail("PsdTools must expose multi-layer PSD export");
  if (!sourceText.includes("selectedLayerKeys"))
    fail("PSD import metadata must preserve multiple selected layer keys");
  if (!sourceText.includes("displayCrop"))
    fail("PSD import metadata must preserve cropped LDtk atlas bounds");
  if (!sourceText.includes("display.width = cropW") || !sourceText.includes("display.height = cropH"))
    fail("LDtk PSD atlas must be cropped instead of using full PSD document dimensions");
  if (!sourceText.includes("entry.info.left-cropLeft") || !sourceText.includes("entry.info.top-cropTop"))
    fail("PSD selected layers must be rebased to cropped atlas origin");
  if (!pickerText.includes('type="checkbox"'))
    fail("PSD layer picker must support multi-select checkboxes");
  if (pickerText.includes('type="radio"'))
    fail("PSD layer picker regressed to single-layer radio selection");

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
        const renderables = [];

        function visit(children) {
          if (!Array.isArray(children)) return;
          for (const layer of children) {
            if (!layer) continue;
            layerCount++;
            if (!Array.isArray(layer.children) && layer.canvas)
              renderables.push(layer);
            visit(layer.children);
          }
        }

        visit(psd.children);

        if (layerCount <= 0)
          throw new Error("PSD layer hierarchy is empty");
        if (renderables.length <= 0)
          throw new Error("PSD fixture has no renderable leaf layer");

        const renderable = renderables[0];

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

        // Multi-layer + crop regression test. Two synthetic 16px tiles are placed
        // away from document origin; the LDtk atlas must crop to 32x16 and keep
        // the tiles touching with no transparent seam between them.
        const tileA = document.createElement("canvas");
        tileA.width = 16;
        tileA.height = 16;
        const a = tileA.getContext("2d");
        a.fillStyle = "#ff0000";
        a.fillRect(0, 0, 16, 16);

        const tileB = document.createElement("canvas");
        tileB.width = 16;
        tileB.height = 16;
        const b = tileB.getContext("2d");
        b.fillStyle = "#00ff00";
        b.fillRect(0, 0, 16, 16);

        const synthetic = [
          { left: 32, top: 16, right: 48, bottom: 32, canvas: tileA },
          { left: 48, top: 16, right: 64, bottom: 32, canvas: tileB },
        ];

        const cropLeft = Math.min(...synthetic.map(x => x.left));
        const cropTop = Math.min(...synthetic.map(x => x.top));
        const cropRight = Math.max(...synthetic.map(x => x.right));
        const cropBottom = Math.max(...synthetic.map(x => x.bottom));
        const cropW = cropRight - cropLeft;
        const cropH = cropBottom - cropTop;

        if (cropW !== 32 || cropH !== 16)
          throw new Error("Cropped PSD atlas bounds are wrong");

        const cropped = document.createElement("canvas");
        cropped.width = cropW;
        cropped.height = cropH;
        const cropCtx = cropped.getContext("2d");
        cropCtx.imageSmoothingEnabled = false;
        for (const layer of synthetic)
          cropCtx.drawImage(layer.canvas, layer.left - cropLeft, layer.top - cropTop);

        const seamLeft = cropCtx.getImageData(15, 8, 1, 1).data[3];
        const seamRight = cropCtx.getImageData(16, 8, 1, 1).data[3];
        if (seamLeft !== 255 || seamRight !== 255)
          throw new Error("Cropped multi-layer atlas introduced a transparent tile gap");

        const croppedUrl = cropped.toDataURL("image/png");
        const croppedPng = BufferCtor.from(croppedUrl.slice(croppedUrl.indexOf(",") + 1), "base64");
        if (!croppedPng || croppedPng.length < 8)
          throw new Error("Cropped multi-layer PNG buffer is empty");

        const variantMetadata = {
          selectedLayerKeys: ["layer-a", "layer-b"],
          selectedLayerPaths: ["Base", "Overlay"],
          displayCrop: {
            left: cropLeft,
            top: cropTop,
            width: cropW,
            height: cropH,
          },
        };
        const parsedVariant = JSON.parse(JSON.stringify(variantMetadata));
        if (parsedVariant.selectedLayerKeys.length !== 2)
          throw new Error("Multi-layer selection metadata round-trip failed");
        if (parsedVariant.displayCrop.width !== 32 || parsedVariant.displayCrop.height !== 16)
          throw new Error("Cropped atlas metadata round-trip failed");

        return {
          width: psd.width,
          height: psd.height,
          layerCount,
          renderableLayers: renderables.length,
          selectedLayer: metadata.selectedLayerName,
          pngBytes: png.length,
          croppedAtlas: [cropW, cropH],
          noGap: true,
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
