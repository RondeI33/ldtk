#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";
import png2icons from "png2icons";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const appDir = path.resolve(scriptDir, "..");
const svgPath = path.join(appDir, "buildAssets", "smartive-logo.svg");
const buildAssetsDir = path.join(appDir, "buildAssets");
const appAssetsDir = path.join(appDir, "assets");

if (!fs.existsSync(svgPath)) {
	throw new Error(`Missing Smartive logo source: ${svgPath}`);
}

fs.mkdirSync(buildAssetsDir, { recursive: true });
fs.mkdirSync(appAssetsDir, { recursive: true });

const png = await sharp(svgPath, { density: 192 })
	.resize(1024, 1024, { fit: "contain" })
	.png({ compressionLevel: 9 })
	.toBuffer();

fs.writeFileSync(path.join(buildAssetsDir, "icon.png"), png);
fs.writeFileSync(path.join(appAssetsDir, "appIcon.png"), png);

const ico = png2icons.createICO(png, png2icons.BICUBIC, 0, false);
if (!ico) {
	throw new Error("Failed to generate Windows icon.ico from Smartive logo");
}
fs.writeFileSync(path.join(buildAssetsDir, "icon.ico"), ico);

const icns = png2icons.createICNS(png, png2icons.BICUBIC, 0);
if (!icns) {
	throw new Error("Failed to generate macOS icon.icns from Smartive logo");
}
fs.writeFileSync(path.join(buildAssetsDir, "icon.icns"), icns);

console.log("Generated LDTK-Smartive branding assets:");
console.log("- app/assets/appIcon.png");
console.log("- app/buildAssets/icon.png (Linux)");
console.log("- app/buildAssets/icon.ico (Windows)");
console.log("- app/buildAssets/icon.icns (macOS)");
