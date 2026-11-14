# `prd` environment

Two stacks, one Terraform state each:

| Stack | Contains | Changes |
|---|---|---|
| `foundation` | Network (VNet, subnets, NSGs), jumpbox, ARCA on Container Instances | Rarely. It's what the app tier stands on |
| `platform` | Public load balancer and the VM Scale Set running the Node app | With every infrastructure configuration the TP measures |
| `observability` | Datadog only: the load test dashboard and the percentiles of the service's distributions | When the dashboard changes. Not destroyed by `mise run down` |

```text
foundation ◀── platform      (platform reads foundation's outputs)
```

`platform` reads `foundation` through `terraform_remote_state`, and **only its outputs**.
`foundation/outputs.tf` is therefore a contract: renaming or removing an output breaks
`platform`'s plan.

Unlike in a long-lived project, `foundation` is not permanent: everything is destroyed
at the end of the TP, and the jumpbox and ARCA are billed by the hour while they exist.
The store, PostgreSQL, lives in `foundation`, so its data outlives a `platform` destroy.

## Prerequisites

Only read by the stacks:

| What | Managed by |
|---|---|
| Resource group `RG-PRODUCTION` (`var.resource_group_name`) and the team's access to it (group `ARQUI-TP2-ADMIN`, Contributor) | [`infra/bootstrap`](../../bootstrap/README.md). Not by `foundation`: a resource group it created would lose the team's role assignment on every destroy. `destroy` empties it and keeps it |
| SSH key `ssh_key` in `RG-PRODUCTION` (`var.ssh_key_name`, `var.ssh_key_group_name`) | Nobody: created by hand. | Created in the Azure portal (SSH keys → Create), which keeps the private key out of Terraform's state. Its private key is `key.pem` at the repository root, gitignored, shared within the team by other means |

## Order

- **Apply** `foundation`, then `platform`. `platform` can't be planned before
  `foundation` has a state.
- **Destroy** `platform`, then `foundation`.

## Commands

The stack is the task's argument. It defaults to `foundation`, except for `destroy`,
which defaults to `platform`.

```sh
mise run infra:bootstrap        # once per group: HCP workspaces + Azure identity
mise run infra:plan platform
mise run infra:apply foundation
mise run infra:destroy platform
mise run infra:validate        # every stack
mise run infra:lint            # fmt check + tflint

mise run up                    # login, apply both stacks, Ansible setup, deploy
mise run down                  # destroy platform, then foundation
```

## HCP Terraform

Each stack keeps its state in, and runs its plans and applies on, an HCP Terraform
workspace: organization `gaudi-followers`, project `arvault-prd`.

| Stack | Workspace |
|---|---|
| `foundation` | `arvault-prd-foundation` |
| `platform` | `arvault-prd-platform` |
| `observability` | `arvault-prd-observability` |

[`infra/bootstrap`](../../bootstrap/README.md) creates both workspaces, their variables,
and the Azure identity the runs authenticate as. Apply it once per group before
anything else.

- **Runs are remote.** `terraform plan` and `apply` upload the repository (minus
  `.terraformignore`) and stream the run's output. The runs authenticate to Azure with
  dynamic provider credentials (OIDC). The local `az login` is not used by Terraform.
- **Variables live in the workspaces**, not in `terraform.tfvars` files. The stacks
  have none. `.terraformignore` keeps any local `*.tfvars` from being uploaded.
- **State is shared and locked.** Every member sees the same deployment. Run
  `terraform login` once per machine.

## Outputs

Nothing is written to disk by Terraform. The scripts read the outputs they need with
[`infra/output.sh`](../output.sh), which calls `terraform output` against the
workspace. Each value is the one in the latest applied state.

| Output | Stack | Read by |
|---|---|---|
| `jumpbox_fqdn` | `foundation` | `ansible/update_vmss_inventory.sh` |
| `arca_uri` | `foundation` | `platform`, into `app_config` |
| `database_url` (sensitive) | `foundation` | `platform`, into `app_config` |
| `lb_fqdn` | `platform` | `perf/run.sh` |
| `app_config` (sensitive) | `platform` | `ansible/deploy.sh`, which writes it to `node/config.local.json` (gitignored) |
| `dashboard_url` | `observability` | People: the dashboard to screenshot and export |

`ansible/vmss_setup.yml` and `perf/run.sh` read the Datadog API key from
`DATADOG_API_KEY` and the site from `DATADOG_SITE`. The `observability` stack reads the
same key, plus an application key, from its workspace's `DD_API_KEY` and `DD_APP_KEY`,
which `infra/bootstrap` sets. `observability` doesn't depend on the other two stacks:
apply it in any order, after the first `arvault.*` metric reached Datadog (see
[`docs/infra/overview.md`](../../../docs/infra/overview.md#observability)).
