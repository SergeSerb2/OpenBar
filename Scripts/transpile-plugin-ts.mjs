import fs from "node:fs";
import vm from "node:vm";

const [sourcePath, sucrasePath] = process.argv.slice(2);
if (!sourcePath || !sucrasePath) {
  console.error("Usage: transpile-plugin-ts.mjs <source.ts> <sucrase.min.js>");
  process.exit(2);
}

const context = vm.createContext({
  __openbarTypeScriptSource: fs.readFileSync(sourcePath, "utf8"),
});
vm.runInContext(fs.readFileSync(sucrasePath, "utf8"), context, { filename: sucrasePath });
const output = vm.runInContext(
  "sucrase.transform(__openbarTypeScriptSource, {transforms:['typescript']}).code",
  context,
  { filename: "<sucrase-transform>" },
);
process.stdout.write(output);
