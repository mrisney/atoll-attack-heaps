#!/usr/bin/env node
// Build the web version, run it in headless Chromium and save screenshots.
//
//   node scripts/snapshot.mjs [options]
//
// Options (all optional):
//   --seed=12345        island seed (default 4242, so runs are comparable)
//   --style=classic     classic | painted | inkmap
//   --shape=single      single | atoll
//   --dist=55           camera distance (zoom)
//   --out=snapshots     output folder
//   --name=shot         file name prefix
//   --walk              also box-select blue squad, order a move, and take a second shot mid-walk
//   --no-build          skip `haxe build-js.hxml`
//   --size=1280x760     viewport
//
// Exit code is non-zero if the page throws or logs an error, so agents can use
// it as a smoke test as well as a way to *see* a change.

import { execSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const [k, v] = a.replace(/^--/, "").split("=");
    return [k, v ?? true];
  })
);

const seed = args.seed ?? "4242";
const style = args.style ?? "classic";
const shape = args.shape ?? "single";
const outDir = resolve(root, args.out ?? "snapshots");
const name = args.name ?? `${shape}-${style}-${seed}`;
const [width, height] = (args.size ?? "1280x760").split("x").map(Number);

if (!args["no-build"]) {
  console.log("Building web version…");
  execSync("haxe build-js.hxml", { cwd: root, stdio: "inherit" });
}

let chromium;
try {
  ({ chromium } = require("playwright"));
} catch {
  console.error("Playwright not found. Run: npm install && npx playwright install chromium");
  process.exit(2);
}

mkdirSync(outDir, { recursive: true });

const params = new URLSearchParams({ seed, style, shape });
if (args.dist) params.set("dist", args.dist);
const url = `file://${join(root, "bin", "index.html")}?${params}`;

// Software GL fallback keeps this working on CI/headless boxes without a GPU.
const browser = await chromium.launch({
  args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
});
const page = await browser.newPage({ viewport: { width, height } });

const problems = [];
page.on("pageerror", (e) => problems.push(`pageerror: ${e.message}`));
page.on("console", (m) => {
  if (m.type() === "error" && !/passive event listener/.test(m.text())) problems.push(`console: ${m.text()}`);
});

await page.goto(url);
try {
  await page.waitForFunction(() => (window.atollFrames ?? 0) > 20, null, { timeout: 60000 });
} catch {
  problems.push("game never reached 20 frames (did it crash on start?)");
}

const shots = [];
const shot = async (suffix) => {
  const file = join(outDir, `${name}${suffix}.png`);
  await page.screenshot({ path: file });
  shots.push(file);
};

await shot("");

if (args.walk) {
  // The camera starts on the blue squad: box-select around the centre, then
  // right-click further up the screen to send them walking.
  await page.mouse.move(width * 0.3, height * 0.25);
  await page.mouse.down();
  await page.mouse.move(width * 0.7, height * 0.75, { steps: 8 });
  await page.mouse.up();
  await page.mouse.click(width * 0.5, height * 0.2, { button: "right" });
  await page.waitForTimeout(1500);
  await shot("-walk");
}

await browser.close();

for (const f of shots) console.log(`saved ${f}`);
if (problems.length) {
  console.error("\nProblems:\n" + problems.map((p) => "  " + p).join("\n"));
  process.exit(1);
}
