#!/usr/bin/env node
/** Render MiniMax cover HTML to an A4 PDF with Hermes' bundled Chromium. */

const fs = require("fs");
const os = require("os");
const path = require("path");
const { pathToFileURL } = require("url");
const { spawnSync } = require("child_process");

function usage() {
  console.error("Usage: node render_cover.js --input <file.html> --out <file.pdf> [--wait <ms>]");
  process.exit(1);
}

function findExecutable(root) {
  if (!root || !fs.existsSync(root)) return null;
  const names = new Set(["chrome", "chromium", "chrome-headless-shell", "headless_shell", "chromium-browser"]);
  const pending = [root];
  while (pending.length) {
    const current = pending.shift();
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const candidate = path.join(current, entry.name);
      if (entry.isDirectory()) pending.push(candidate);
      if (entry.isFile() && names.has(entry.name)) {
        try {
          fs.accessSync(candidate, fs.constants.X_OK);
          return candidate;
        } catch (_) {}
      }
    }
  }
  return null;
}

function chromiumPath() {
  const configured = process.env.AGENT_BROWSER_EXECUTABLE_PATH;
  if (configured) {
    try {
      fs.accessSync(configured, fs.constants.X_OK);
      return configured;
    } catch (_) {}
  }
  return findExecutable(process.env.PLAYWRIGHT_BROWSERS_PATH || "/opt/hermes/.playwright");
}

const args = process.argv.slice(2);
let inputFile = null;
let outFile = null;
let waitMs = 800;

for (let i = 0; i < args.length; i += 1) {
  if (args[i] === "--input" && args[i + 1]) inputFile = args[++i];
  else if (args[i] === "--out" && args[i + 1]) outFile = args[++i];
  else if (args[i] === "--wait" && args[i + 1]) waitMs = Number.parseInt(args[++i], 10);
}

if (!inputFile || !outFile || !Number.isFinite(waitMs) || waitMs < 0) usage();
if (!fs.existsSync(inputFile)) {
  console.error(JSON.stringify({ status: "error", error: `File not found: ${inputFile}` }));
  process.exit(1);
}

const chromium = chromiumPath();
if (!chromium) {
  console.error(JSON.stringify({
    status: "error",
    error: "Hermes Chromium executable not found",
    hint: "Rebuild the Hermes image so its bundled agent-browser runtime is restored",
  }));
  process.exit(2);
}

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "minimax-cover-"));
const tempHtml = path.join(tempDir, "cover.html");
const resolvedOut = path.resolve(outFile);

try {
  const source = fs.readFileSync(inputFile, "utf8");
  const pageStyle = "<style>@page { size: A4; margin: 0; }</style>";
  const printable = /<\/head>/i.test(source)
    ? source.replace(/<\/head>/i, `${pageStyle}</head>`)
    : `${pageStyle}${source}`;
  fs.writeFileSync(tempHtml, printable);

  const result = spawnSync(chromium, [
    "--headless",
    "--no-sandbox",
    "--disable-gpu",
    "--disable-dev-shm-usage",
    "--allow-file-access-from-files",
    "--run-all-compositor-stages-before-draw",
    `--virtual-time-budget=${waitMs}`,
    "--no-pdf-header-footer",
    `--print-to-pdf=${resolvedOut}`,
    pathToFileURL(tempHtml).href,
  ], { encoding: "utf8" });

  if (result.status !== 0 || !fs.existsSync(resolvedOut)) {
    throw new Error((result.stderr || result.stdout || `Chromium exited ${result.status}`).trim());
  }

  const stat = fs.statSync(resolvedOut);
  if (stat.size < 5000) {
    throw new Error("Output PDF is suspiciously small; check cover.html for render errors");
  }

  console.log(JSON.stringify({
    status: "ok",
    out: outFile,
    size_kb: Math.round(stat.size / 1024),
  }));
} catch (error) {
  console.error(JSON.stringify({ status: "error", error: String(error) }));
  process.exitCode = 3;
} finally {
  fs.rmSync(tempDir, { recursive: true, force: true });
}
