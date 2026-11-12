// Checks the report against the rules the assignment grades on.
//
// Reads, on stdin, the JSON that `mise run report:check` extracts from the
// compiled document with `typst eval`:
//   { evidencia: [{id, descripcion, ubicacion, lineas?, commit?}], citas: [id],
//     paginas: n, pendientes: n }
//
// Fails on:
//   - a body over the page limit (cover, outline and evidence index excluded)
//   - a cited [E-NN] that is not declared in evidencia.yml
//   - a declared ID whose `ubicacion` does not exist in the repo (at its
//     `commit`, when it has one)
//   - a declared ID with `lineas` and no `commit`: lines on main drift
//   - `lineas` past the end of the file at that commit
//   - a duplicated ID
// Warns on a declared ID that nothing cites, and on `#pendiente` blocks.
// With --final, the warnings fail too: the assignment rejects a report with
// undeveloped sections, and an uncited ID backs nothing.

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const PAGE_LIMIT = 30;
const root = process.env.REPO_ROOT ?? process.cwd();
const final = process.argv.includes("--final");

// The content of `<commit>:<path>`, or null when either does not exist.
function gitShow(object) {
  try {
    return execFileSync("git", ["-C", root, "show", object], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
  } catch {
    return null;
  }
}

const data = JSON.parse(readFileSync(0, "utf8"));
const errors = [];
const warnings = [];

const declared = data.evidencia.map((e) => e.id);
const cited = new Set(data.citas);

for (const id of new Set(declared)) {
  if (declared.filter((d) => d === id).length > 1) {
    errors.push(`${id} is declared more than once in evidencia.yml`);
  }
}

for (const id of cited) {
  if (!declared.includes(id)) {
    errors.push(`[${id}] is cited but not declared in evidencia.yml`);
  }
}

for (const e of data.evidencia) {
  if (e.lineas !== undefined && e.commit === undefined) {
    errors.push(`${e.id}: cites lines without a commit; lines on main drift`);
  }
  if (e.commit === undefined) {
    if (!existsSync(resolve(root, e.ubicacion))) {
      errors.push(`${e.id}: ${e.ubicacion} does not exist`);
    }
    continue;
  }
  // Pinned: the file and its lines are checked at that commit, not in the
  // working tree, where they may have moved or been renamed since.
  const content = gitShow(`${e.commit}:${e.ubicacion}`);
  if (content === null) {
    errors.push(`${e.id}: ${e.ubicacion} does not exist at ${e.commit}`);
    continue;
  }
  if (e.lineas !== undefined) {
    const total = content.split("\n").length - (content.endsWith("\n") ? 1 : 0);
    const last = Math.max(...String(e.lineas).split(/[,-]/).map(Number));
    if (!Number.isInteger(last) || last < 1 || last > total) {
      errors.push(
        `${e.id}: lines ${e.lineas} out of ${e.ubicacion} at ${e.commit} (${total} lines)`,
      );
    }
  }
}

for (const id of new Set(declared)) {
  if (!cited.has(id)) warnings.push(`${id} is declared but never cited`);
}

if (data.paginas === null) {
  errors.push("could not find the body markers; is plantilla.typ in use?");
} else if (data.paginas > PAGE_LIMIT) {
  errors.push(`the body is ${data.paginas} pages, the limit is ${PAGE_LIMIT}`);
}

if (data.pendientes > 0) {
  warnings.push(`${data.pendientes} #pendiente block(s) left`);
}

const failing = final ? [...errors, ...warnings] : errors;

console.log(`Body: ${data.paginas} / ${PAGE_LIMIT} pages`);
console.log(`Evidence: ${declared.length} declared, ${cited.size} cited`);
for (const w of warnings) console.log(`${final ? "ERROR" : "WARN "} ${w}`);
for (const e of errors) console.log(`ERROR ${e}`);

process.exit(failing.length > 0 ? 1 : 0);
