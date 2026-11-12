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
//   - a `repositorio: tp1` entry without `commit`, or whose file does not
//     exist at it. tp1's repo is private: without access to it (as in CI),
//     its entries are a warning instead
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

// tp1's evidence lives in its own repository, which is private. It is read
// through `gh`, with the caller's GitHub login. Returns the file at the
// commit, null when it does not exist there, or undefined when tp1 cannot be
// read at all (no gh, no login, no access: CI's token sees only this repo).
const TP1 = "repos/tcorzo/fiuba-2026C2-arq-tp1";

// `gh api` with the caller's login: its stdout, or null when it fails.
function ghApi(...args) {
  try {
    return execFileSync("gh", ["api", ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
  } catch {
    return null;
  }
}

let tp1Readable;
function tp1Show(commit, path) {
  tp1Readable ??= ghApi(TP1, "--silent") !== null;
  if (!tp1Readable) return undefined;
  return ghApi(
    "-H",
    "Accept: application/vnd.github.raw",
    `${TP1}/contents/${path}?ref=${commit}`,
  );
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
  const tp1 = e.repositorio === "tp1";
  if (e.repositorio !== undefined && !tp1) {
    errors.push(`${e.id}: unknown repositorio "${e.repositorio}"`);
    continue;
  }
  if (tp1 && e.commit === undefined) {
    errors.push(`${e.id}: tp1 evidence needs a commit`);
    continue;
  }
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
  const content = tp1
    ? tp1Show(e.commit, e.ubicacion)
    : gitShow(`${e.commit}:${e.ubicacion}`);
  if (content === undefined) {
    warnings.push(`${e.id}: cannot read tp1's repository to check it`);
    continue;
  }
  if (content === null) {
    errors.push(
      `${e.id}: ${tp1 ? "tp1's " : ""}${e.ubicacion} does not exist at ${e.commit}`,
    );
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
