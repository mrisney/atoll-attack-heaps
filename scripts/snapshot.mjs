#!/usr/bin/env node
// Build the web version, run it in headless Chromium and save screenshots.
//
//   node scripts/snapshot.mjs [options]
//
// Options (all optional):
//   --seed=12345        island seed (default 4242, so runs are comparable)
//   --style=painted     painted | sketch | classic | inkmap
//   --shape=single      single | atoll
//   --dist=55           camera distance (zoom)
//   --out=snapshots     output folder
//   --name=shot         file name prefix
//   --walk              also box-select blue squad, order a move, and take a second shot mid-walk
//   --fly=0.4,0.2       click the minimap at (u,v) fractions to fly there; ';' for several
//   --at=-38,0          start the camera looking at this world point (x,y)
//   --figures=rigged    draw units as the rigged FBX character
//   --weather=rain      sunny | fog | rain (default: the style's own)
//   --autoland          the blue ship lands its crew at its home beach at once
//   --blueai            a computer commander for blue too (watch AI vs AI)
//   --bombard           once blue is ashore, its ship sails round to shell red's beach
//   --naval             naval test: both ships out at sea, both selectable, nobody lands
//   --gallery           line up one rigged figure per kind and take at the view centre
//   --untiltick=750,1200   wait for these sim ticks (30/s) and take a shot at each
//   --after=12          after everything else, wait this many seconds and take one more shot
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
const style = args.style ?? "painted";
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
if (args.at) params.set("at", args.at);
if (args.figures) params.set("figures", args.figures);
if (args.gallery) params.set("gallery", "1");
if (args.weather) params.set("weather", args.weather);
if (args.autoland) params.set("autoland", "1");
if (args.blueai) params.set("blueai", "1");
if (args.bombard) params.set("bombard", "1");
if (args.naval) params.set("naval", "1");
// Software rendering is slow (seconds per frame); let the sim catch up to real time.
params.set("catchup", args.catchup ?? "10");
const url = `file://${join(root, "bin", "index.html")}?${params}`;

// Software GL fallback keeps this working on CI/headless boxes without a GPU.
const browser = await chromium.launch({
  args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
});
const page = await browser.newPage({ viewport: { width, height } });

const problems = [];
page.on("pageerror", (e) => problems.push(`pageerror: ${problems.length ? e.message : e.stack}`));
page.on("console", (m) => {
  if (m.type() === "error" && !/passive event listener/.test(m.text())) problems.push(`console: ${m.text()}`);
});

// --untiltick: hold the sim at the first requested tick from the very start (the
// normal first shot alone takes minutes in software rendering).
if (args.untiltick) {
  const first = Number(String(args.untiltick).split(",")[0]);
  await page.addInitScript((n) => (window.atollHoldTick = n), first);
}
await page.goto(url);
try {
  await page.waitForFunction(() => (window.atollFrames ?? 0) > 20, null, { timeout: 180000 });
} catch {
  problems.push("game never reached 20 frames (did it crash on start?)");
}

const shots = [];
const shot = async (suffix) => {
  const file = join(outDir, `${name}${suffix}.png`);
  await page.screenshot({ path: file, timeout: 480000 });
  shots.push(file);
};

await shot("");

if (args.fly) {
  // --fly=u,v[;u,v…]: click the minimap at fractions of its size (0,0 = top-left)
  // to fly the camera there, then take a shot at each spot (-fly1, -fly2…).
  const spots = String(args.fly).split(";").map((p) => p.split(",").map(Number));
  const mm = { x: 16, y: height - 188, size: 172 };
  for (let k = 0; k < spots.length; k++) {
    const [u, v] = spots[k];
    await page.mouse.click(mm.x + u * mm.size, mm.y + v * mm.size);
    await page.waitForTimeout(2500);
    await shot(`-fly${k + 1}`);
  }
}

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

if (args.untiltick) {
  // Wait for the sim to reach a tick (30 per second), then take a shot.
  for (const t of String(args.untiltick).split(",")) {
    await page.evaluate((n) => (window.atollHoldTick = n), Number(t));
    await page.waitForFunction((n) => Number((window.atollSim ?? "tick=0").split(" ")[0].slice(5)) >= n, Number(t), { timeout: 600000 });
    await page.waitForTimeout(3000); // a couple of frames at the held tick
    await shot("-t" + t);
  }
  await page.evaluate(() => (window.atollHoldTick = undefined));
}

if (args.after) {
  // Let the game run on (ships sailing, crews landing, fights), then one more shot.
  await page.waitForTimeout(Number(args.after) * 1000);
  await shot("-after");
}

await browser.close();

for (const f of shots) console.log(`saved ${f}`);
if (problems.length) {
  console.error("\nProblems:\n" + problems.map((p) => "  " + p).join("\n"));
  process.exit(1);
}
