# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project context

FIUBA **Arquitectura del Software** (75.73/TB034), 2nd semester of 2026 — **TP 2: cloud deploy**.

We migrate **arVault**'s currency-exchange service to **Azure**, starting from our TP 1 implementation (the tactics that measured best). The infrastructure is a VM Scale Set behind an Azure Load Balancer, a jumpbox for admin access, a managed storage (Redis or another PaaS database) and a mock of **ARCA**'s API on Azure Container Instances. We measure it on 1 node and scaled to 2, explain what we see, and implement **one or two** superior tactics chosen from bottlenecks we observed with evidence. Extra tactics earn nothing and are not read.

**The deliverable is the report, not the code.** Code and infrastructure changes exist to produce measurable evidence for the report.

Due **2026-11-19 17:59**, as a PDF **inside this repository**. Partial deliveries are not accepted. Repo: `tcorzo/fiuba-2026C2-arq-tp2` (**public**), base branch `main`. TP 1 is `tcorzo/fiuba-2026C2-arq-tp1`; its report is the source for section 3 of this one.

`README.md` is the assignment. Read it before any task that touches the report, the evidence or the measurements: the rules below summarise it, they do not replace it.

## Language policy (UTMOST importance)

**Code surfaces are ENGLISH. The report and its supporting prose are es-AR.** The split is by audience: code is read by us and by the tooling, the report is read by the teachers.

**English applies regardless of the language used in conversations, issues, or Slack.** We discuss this TP in Spanish and always will — that changes nothing about what gets written to a file. This covers variable and function names, comments, commit messages, and **any text embedded in source code**: log lines, error strings, Artillery scenario names, metric names shipped to Datadog, Terraform resource names.

| Surface | Rule | Example ✅ | Example ❌ |
|---|---|---|---|
| Commit messages, PR titles, branch names | English, conventional | `feat(infra): add a managed redis instance` | `feat(infra): agregar redis` |
| Identifiers and comments in `node/`, `infra/`, `ansible/`, `perf/*.yaml` | English | `authorizationCode`, `arca_timeout_ms` | `codigoAutorizacion` |
| Log lines and metric names | English | `arca.validation.rejected` | `arca.validacion.rechazada` |
| **The report** (`docs/informe/`), Typst identifiers included | **es-AR** | `#tactica(problema: …, compromiso: …)` | `#tactic(problem: …)` |
| PlantUML labels in `docs/diagramas/` | **es-AR** | `Balanceador de carga` | `Load balancer` |
| `perf/predicciones.md`, `evidencia/README.md` | **es-AR** | — | — |

**Carve-outs:** the root `README.md` is the course-provided assignment — do not translate it, reword it, or reorganise it. `docs/infra/overview.md` is written in English; keep it that way. ARCA's API contract is fixed by the course (`dni`, `ok`, `codigoAutorizacion`): use those field names on the wire, and English names everywhere else.

**Why:** mixing languages inside a single surface is what actually hurts. Picking one language per surface removes the decision from every commit.

### Report vocabulary

es-AR as an engineer writes it, not as a dictionary translates it: a technical term the field says in English stays in English, in plain text. One term per thing.

| Literal translation | Term the report uses |
|---|---|
| pedido | request |
| balanceador de carga | load balancer |
| conjunto de escalado | VMSS |
| núcleo | core |
| captura | screenshot |
| tiempo de espera vencido | timeout |
| corrida | ejecución |
| tablero (de Datadog) | dashboard |
| cambio (una llamada al endpoint de exchange) | exchange: "un exchange respondido". "Cambio" queda para cambios de código o de infraestructura, y "cambio de monedas" para el negocio |

Domain and statistics terms stay Spanish: mediana, latencia, escenario, réplica, nodo, predicción, hipótesis.

## Evidence (UTMOST importance)

**Every relevant claim in the report cites an evidence ID `[E-NN]`.** A claim without one is unsupported. The teachers verify claims by random sampling: **if one cited piece of evidence does not back its claim, or is inconsistent with the repo, the whole section that contains it counts as unsupported.** Fabricated or altered evidence is a serious offence.

| Rule | How |
|---|---|
| Declare every ID | `docs/informe/evidencia.yml`: `id`, `descripcion`, `ubicacion` (path from the repo root) and optional `lineas`. The template renders the evidence index from it. An ID is never reused or renumbered. |
| Cite in prose | Write the ID in brackets, as the assignment does: `La p95 sube a 410 ms [E-07].` The template links it to its index row. An undeclared ID renders red. |
| Evidence lives in the repo | The infrastructure is destroyed at the end. Raw Artillery reports in `perf/results/<case>/` next to the scenario that produced them (`perf/run.sh` writes them with `--output`); Datadog screenshots that show the test's time range, plus the exported dashboard JSON; infra outputs and log extracts in `evidencia/<case>/`. Links to Datadog or Azure are never the only evidence. |
| Infra evidence per configuration | For every measured configuration, while it is deployed: the output of `terraform state list` and `terraform output` of each stack, and `az vmss list-instances` (only non-identifying columns), saved under `evidencia/<case>/`. Plus the Terraform/Ansible change in the commit history. |
| Code claims | A reproducible execution, request and response, that shows the behaviour. A code citation alone is not enough. |
| ARCA | A log extract with approved validations (with their authorisation code) and rejected ones. |
| Raw is raw | Evidence files are committed exactly as the command wrote them. The pre-commit whitespace fixers skip `perf/results/` and `evidencia/` for this reason. Never edit, trim or "clean up" an output. If a number was not observed in a run, it does not go in the report. |
| **No secrets** | API keys, private keys, `terraform.tfvars`, `terraform.tfstate`: never in git. The repo is **public**. Read every output and screenshot before committing it. A leaked key gets revoked and replaced, not just deleted. `gitleaks` runs on every commit and in CI; it does not replace reading. |

`mise run report:check` fails on an undeclared citation, on a declared `ubicacion` that does not exist, and on a body over 30 pages. With `--final` it also fails on `#pendiente` blocks and on IDs nobody cites. Run it before opening a PR that touches the report.

## Predictions before measuring (UTMOST importance)

Before **each** load test (1 node, scaled, and each tactic) the group records a **hypothesis with a numeric prediction** on at least one metric, and the reasoning behind it (code, infrastructure, TP 1 results). After measuring, the report compares and explains the difference. A wrong prediction is not penalised; the reasoning is graded.

- Predictions go in `perf/predicciones.md`, **committed before the results of that test**. The commit history is the proof, so the prediction and the results are **separate commits**, prediction first.
- Never edit a prediction after its results exist. The comparison goes in the report, through `#prediccion(metrica:, predicho:, observado:, evidencia:)`.
- For the scaled case, the prediction states whether throughput scales proportionally with the node count and, if not, which component stops it.
- **This is why PRs are merged with a merge commit, never squashed**: a squash folds the prediction and the results into one commit and destroys the proof.

## Measurement discipline (UTMOST importance)

| Rule | Consequence of breaking it |
|---|---|
| Every test runs from outside Azure, and **every test that is compared with another runs from the same location** (same machine, same network). The report states where the load generator ran, its connection type and bandwidth. | Latency includes the internet round trip; a different location changes it. |
| Measure the **baseline network latency** against `/` (no load, no ARCA, no Redis) before the tests, and use it when interpreting every latency. | A latency delta smaller than the baseline's variation is noise. |
| Every infrastructure change goes through `infra/` (Terraform) or `ansible/`. | Changes made in the Azure portal or over SSH are **not implemented** for the assignment: they are not reproducible. |
| Scaling means changing `instances` on the VMSS in Terraform, applying it, then running the Ansible setup and deploy again. | A new instance without the app is a backend the load balancer probes and then routes to. |
| Record the infra evidence (see *Evidence*) for every configuration while it is deployed. | Once destroyed, there is no way to prove what ran. |
| There is no nginx in this deployment: the Azure Load Balancer takes its place in the request path. A TP 1 tactic that lived in nginx is reconsidered explicitly in section 3, not silently dropped. | The report must say what happened to each TP 1 tactic and why. |

## Infrastructure

| Path | What it is |
|---|---|
| `infra/` | Terraform. Its layout, the order to apply it and its tasks are documented in `docs/infra/overview.md`; read that instead of assuming a structure. State and runs live in **HCP Terraform** (org `gaudi-followers`, project `arvault-prd`, one workspace per stack, remote execution); `infra/bootstrap` (applied by the subscription's Owner) creates the workspaces, their variables, the Azure OIDC identity, and manages the resource group `RG-PRODUCTION` with the team's Contributor access; the prd stacks only read that resource group. The stacks' secrets are workspace variables, not `terraform.tfvars`. Only `infra/bootstrap` has a local `terraform.tfvars` and `terraform.tfstate`, never committed. |
| `ansible/` | `setup.sh` refreshes the VMSS inventory and installs Node, pm2 and the Datadog agent; `deploy.sh` zips `node/` and deploys it. Both go through the jumpbox. |
| `node/` | The service. Starts as the course's sample app (`GET /:dni` → ARCA); gets replaced by our TP 1 service with the `dni` field and the ARCA call. |
| `node/config.js` | Reads `node/config.local.json` (gitignored), which `ansible/deploy.sh` writes from the `platform` stack's `app_config` output. Environment variables override it. A new runtime setting is a key in `app_config` plus a line in `config.js`. |
| `perf/` | Artillery. `run.sh <scenario> <output>` runs `<scenario>.yaml` against the load balancer and writes the raw report. `DATADOG_API_KEY` comes from the environment, never from a file in the repo. |
| `perf/predicciones.md` | The predictions, see above. |
| `perf/results/<case>/` | Raw Artillery reports. Tracked on purpose. |
| `evidencia/<case>/` | Infra outputs, log extracts, dashboard JSON. Tracked on purpose. |
| `docs/informe/` | The report, in Typst. `informe.typ` is the entry point, `plantilla.typ` the template, `secciones/*.typ` one file per section in the assignment's order, `secciones/tacticas/<tactic>.typ` one per tactic, `evidencia.yml` the evidence index. |
| `docs/diagramas/` | PlantUML sources and their committed renders. |
| `scripts/check-report.mjs` | The checks behind `mise run report:check`. |

Secrets live in the HCP Terraform workspace variables, in `infra/bootstrap/terraform.tfvars` (gitignored) and in the `DATADOG_API_KEY` environment variable, which both Ansible and Artillery read. Terraform writes nothing to disk: the scripts read outputs with `infra/output.sh <stack> <output>`. `.terraformignore` keeps `*.tfvars`, `*.pem` and everything outside `infra/` out of the uploads to HCP Terraform.

## The report

The structure is fixed by the assignment (README.md, *Formato y extensión*), and `informe.typ` includes the sections in that order: resumen ejecutivo (with the key-results table), entorno, punto de partida desde el TP 1, arquitectura desplegada, Docker Compose vs. nube, integración con ARCA, caso 1 nodo, caso escalado, tácticas superadoras, decisiones descartadas, conclusiones, uso de herramientas de IA, and the evidence index.

**Hard limit: 30 pages** (A4, 11 pt, 2.5 cm margins, which `plantilla.typ` sets), diagrams and screenshots included. Cover, table of contents and evidence index do not count. What exceeds the limit is not read, and a conclusion that depends on unread content is unsupported. Annexes are not graded: everything that should be graded goes in the body.

| Element | Rule |
|---|---|
| Key-results table | `#tabla-resultados(...)` in `resumen.typ`: one row per measured case (1 node, scaled, each tactic) with nodes, scenario, sustained throughput, median and p95 latency, error rate, limiting component and evidence ID. It is what the teachers ask about in the final exam; every number comes from its raw report. |
| Tactic | `#tactica(nombre:, qa:, base:, commit:, problema:, prediccion:, implementacion:, resultados:, compromiso:)` in `secciones/tacticas/<tactic>.typ`, included from `tacticas.typ`. Missing fields render red. |
| Prediction vs. result | `#prediccion(metrica:, predicho:, observado:, evidencia:)`. |
| Unwritten content | `#pendiente[...]`. Renders a yellow box; `report:check --final` fails while any remains. The assignment rejects deliveries with undeveloped or filler sections. |
| Repo links | `#commit("ref")`, `#sha("abc1234")`, `#diff(a, b)`, `#codigo("node/app.js", "11-24", en: "<sha>")`. `en:` is required: a citation against `main` drifts as `main` moves. TP 1 links take `repo: repositorio-tp1`. These links do not replace `[E-NN]`. |
| Prose | ASD-STE100 applied to Spanish: at most 25 words per sentence, active voice, literal verbs, one term per thing. After each `.typ` edit, run `typstyle -i` and `mise run report`, then look at the rendered page. |
| Headings | Levels 1–3 are numbered and listed in the index; level 4 and deeper render unnumbered and unlisted. |
| Figures | Under `docs/informe/figuras/<case>/`. |
| PDF | `docs/informe/informe.pdf` is gitignored while we work. The delivery PR adds it with `git add -f`. |

## AI disclosure (UTMOST importance)

AI use is allowed and does not cost marks by itself; the group must understand, verify and be able to defend everything delivered. Section 12 (`secciones/uso-de-ia.typ`) must list the tools and what they were used for, and **at least one concrete case** where the tool proposed something wrong, incomplete, outdated or unfit for this system (e.g. a Terraform resource or attribute that does not exist, an insecure configuration, a conclusion the metrics do not support): what it proposed, how we caught it — ideally with an `[E-NN]` — and what we did instead.

**What this means for work done in this session:** add a row to the usage table in `uso-de-ia.typ` in the same PR as the work. When Claude proposes something that turns out wrong and gets corrected, **say so explicitly to the user and suggest recording it** — those cases are required content, and they are easy to lose. Never present generated analysis as a measured result. Commits made with Claude carry the `Co-Authored-By: Claude …` trailer, which makes the record verifiable from `git log`.

## Commands

Tooling and tasks are managed by **mise** — there is no Makefile and no justfile. `mise tasks` lists everything.

Two things cannot be pinned in `mise.toml` and are installed once per machine: **Graphviz** (`apt`/`dnf install graphviz`, for PlantUML) and the PlantUML jar (`mise run diagrams:fetch`). Plus the accounts and keys in README.md, *Setup* (Azure, Docker Hub, Datadog, `key.pem`).

On a fresh clone:

```sh
mise trust                 # needed once per clone
mise install               # every pinned tool
mise run hooks:install     # wire the pre-commit hooks
```

The infrastructure, Ansible, app and load-test tasks are documented with the infrastructure (`docs/infra/overview.md`); `mise tasks` lists them.

The report and repo hygiene:

```sh
mise run report                  # compile docs/informe/informe.typ to PDF
mise run report:watch            # re-compile on every save
mise run report:open             # compile and open the PDF
mise run report:check [--final]  # page limit, citations, evidence paths
mise run diagrams                # render docs/diagramas/*.puml to SVG and PNG
mise run lint                    # all pre-commit hooks over what this branch changed
```

`mise run report` deliberately does not depend on `diagrams`: PlantUML's layout changes with the Graphviz version. Re-render on purpose and look at the PNG before committing it.

CI (`.github/workflows/checks.yml`) runs the hooks over the PR's changed files, a full-history `gitleaks` scan, and `report` + `report:check` on every PR.

## Git commits

All commit messages **must** follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/), written in English.

Format: `<type>(<scope>): <subject>`

- **Types**: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `ci`, `build`, `style`, `revert`
- **Scope** (optional): `node`, `infra`, `ansible`, `perf`, `report`, `diagrams`, `evidence`
- **Subject**: imperative, lowercase, no trailing period

Examples:

- `feat(infra): add a managed redis instance`
- `feat(node): validate the dni against arca before the exchange`
- `perf(infra): scale the vmss to 2 instances`
- `docs(perf): predict the scaled case`
- `docs(evidence): add the 1-node artillery reports`

Convention worth keeping: `perf:` is for changes that alter measurement conditions (instance count, scenarios, VM sizes), `feat:` and `refactor:` for changes to the service under test. That makes the log readable as "which commits could have moved the numbers".

### Branches, PRs and merges

- Branch names: `<type>/<short-english-description>`, e.g. `feat/arca-integration`. A measured case or tactic goes on `case/<name>`, e.g. `case/1-node`, `case/scaled`, `case/<tactic>`. Tag the exact commit a load test ran on `measured/<name>` and push the tag; tags and branches never share a name.
- On a case branch the order of commits is: the infra change, the prediction, then the results and evidence. Never rebase a pushed branch; merge `origin/main` in.
- PRs are merged with a **merge commit**. Squash would destroy the prediction-before-results proof. The PR title becomes the merge commit subject, so **it MUST be a conventional commit** — `.github/workflows/pr-title.yml` enforces it on every non-draft PR; titles prefixed `WIP` are skipped.
- Reference issues in the PR body (`Closes #N`), never in the title.
- Repository settings this relies on: squash and rebase merges disabled, `merge_commit_title=PR_TITLE`.
