# Infrastructure cheatsheet

The mise tasks that manage the infrastructure, and when to run each. Credentials come
first: see [`infra_setup.md`](infra_setup.md). `mise tasks` lists every task.

Stacks: `foundation` (network, jumpbox, ARCA) and `platform` (load balancer, VMSS).
**Apply `foundation` before `platform`; destroy `platform` before `foundation`.**

## Once

| Command | When |
|---|---|
| `mise trust && mise install` | Once per clone: installs Terraform, az, Ansible, Node, etc. at the pinned versions |
| `mise run hooks:install` | Once per clone, before the first commit |
| `mise run infra:bootstrap` | Once per group, by the subscription's Owner. **Already applied.** Again only to recreate the HCP workspaces, rotate a workspace secret or change the Azure identity |

## Bring everything up / down

| Command | When |
|---|---|
| `mise run up` | To start a work or measurement session from nothing. Runs `az login`, applies `foundation` and `platform` **without asking**, then `ansible:setup` and `app:deploy`. Needs `DATADOG_API_KEY` and `DATADOG_SITE` |
| `mise run down` | When you stop working or measuring: everything is billed by the hour. Destroys `platform`, then `foundation`, asking before each. Keeps `RG-PRODUCTION` and the team's access |

## Terraform, one stack at a time

The stack is the argument. It defaults to `foundation`, except for `destroy`, which
defaults to `platform`.

| Command | When |
|---|---|
| `mise run infra:init <stack>` | The first time on a machine, and after changing providers or the `cloud` block. Other tasks fail with "Backend initialization required" otherwise |
| `mise run infra:plan <stack>` | Before every apply, to review the changes. Also to check that nothing drifted (expect "No changes") |
| `mise run infra:apply <stack>` | After a change in `infra/` (shows the plan and asks). `foundation` first |
| `mise run infra:destroy <stack>` | To tear down only one stack, e.g. `platform` to recreate the VMSS while keeping the jumpbox and ARCA. `platform` first |

Plans and applies run remotely in HCP Terraform (`arvault-prd-foundation`,
`arvault-prd-platform`); the run also shows up in app.terraform.io.

## Checks before committing a Terraform change

| Command | When |
|---|---|
| `mise run infra:fmt` | After editing any `.tf` file: formats them |
| `mise run infra:validate` | After editing any `.tf` file: validates the three stacks, bootstrap included. Needs no credentials |
| `mise run infra:lint` | Before opening the PR: format check + tflint. CI runs the same hooks |
| `mise run lint` | Before opening the PR: every pre-commit hook over what the branch changed |

## The app on the VMSS

Both go through the jumpbox, need `key.pem` and an `az login` session, and run after
both stacks are applied.

| Command | When |
|---|---|
| `mise run ansible:setup` | After every `platform` apply that creates instances (first deploy, scaling): installs Node, pm2 and the Datadog agent. Needs `DATADOG_API_KEY` and `DATADOG_SITE` |
| `mise run app:deploy` | After `ansible:setup`, and after every change in `node/`. Also writes `node/config.local.json` from the `app_config` output, seeds the database if it is empty, and fails if the app doesn't answer `GET /` |
| `mise run app:test` | Before deploying a change in `node/`. Local, needs no infrastructure |

Check that it answers: `curl "http://$(infra/output.sh platform lb_fqdn)/"`.

On the first deploy, the task `Stop old version` fails with `Process or Namespace
server.js not found` and Ansible prints `...ignoring`: there is no process to stop yet.
The deploy is fine if the recap shows `failed=0`.

## Load tests

| Command | When |
|---|---|
| `mise run perf:install` | Once per clone, before the first `perf:run` |
| `mise run perf:run <scenario> <output>` | With the app deployed, **after committing the prediction**. `<scenario>` is a file in `perf/` without `.yaml` (e.g. `baseline`, `exchange`); `<output>` is relative to `perf/`, without `.json` (e.g. `results/1-node/exchange`). Needs `DATADOG_API_KEY` and `DATADOG_SITE` |

## Common workflows

**Scale the VMSS** (change `instances` in Terraform, never in the portal):

```sh
mise run infra:plan platform
mise run infra:apply platform
mise run ansible:setup        # the new instances have no app yet
mise run app:deploy
```

**Deploy a code change:** `mise run app:test`, then `mise run app:deploy`.

**Read an output** (FQDNs, ARCA's URI): `infra/output.sh <stack> <output> [-raw|-json]`,
e.g. `infra/output.sh foundation jumpbox_fqdn`.

**Evidence of a measured configuration** (while it is deployed, into `evidencia/<case>/`):

```sh
terraform -chdir=infra/envs/prd/foundation state list
terraform -chdir=infra/envs/prd/foundation output
terraform -chdir=infra/envs/prd/platform state list
terraform -chdir=infra/envs/prd/platform output
az vmss list-instances -g RG-PRODUCTION -n "$(infra/output.sh platform vmss_name)" \
  --query "[].{instance:instanceId, size:sku.name, zone:zones[0], state:provisioningState}" -o table
```

Only non-identifying columns: no subscription IDs, no IPs.

Read every output before committing it: the repository is public.
