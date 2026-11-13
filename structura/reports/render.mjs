import { readFile, writeFile, access } from "node:fs/promises";
import { chromium } from "playwright";
import { reportHTML, validateReport } from "./template.mjs";
const [input, output] = process.argv.slice(2);
if (!input || !output)
  throw new Error("Usage: node reports/render.mjs analysis.json report.pdf");
const result = JSON.parse(await readFile(input, "utf8"));
validateReport(result);
let executablePath = process.env.CHROMIUM_PATH;
if (!executablePath && process.platform === "darwin") {
  const path = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
  try {
    await access(path);
    executablePath = path;
  } catch {}
}
const browser = await chromium.launch({
  headless: true,
  ...(executablePath ? { executablePath } : {}),
  args: process.env.CHROMIUM_NO_SANDBOX === "1" ? ["--no-sandbox"] : [],
});
try {
  const context = await browser.newContext({ javaScriptEnabled: false });
  await context.route("**/*", (route) => route.abort());
  const page = await context.newPage();
  await page.setContent(reportHTML(result), { waitUntil: "load" });
  const pdf = await page.pdf({
    format: "A4",
    printBackground: true,
    preferCSSPageSize: true,
    displayHeaderFooter: true,
    headerTemplate:
      '<div style="width:100%;margin:0 17mm;font:8px Arial;color:#8492a8;display:flex;justify-content:space-between"><span>STRUCTURA / STRUCTURAL ANALYSIS</span><span>EDUCATIONAL &amp; RESEARCH USE</span></div>',
    footerTemplate:
      '<div style="width:100%;margin:0 17mm;font:8px Arial;color:#8492a8;display:flex;justify-content:space-between"><span>Structura 0.1.0 · Julia computation engine</span><span><span class="pageNumber"></span> / <span class="totalPages"></span></span></div>',
  });
  await writeFile(output, pdf);
} finally {
  await browser.close();
}
