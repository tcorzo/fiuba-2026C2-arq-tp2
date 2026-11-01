# `prd` environment

Two stacks, one Terraform state each:

| Stack | Contains | Changes |
|---|---|---|
| `foundation` | Resource group, network (VNet, subnets, NSGs), jumpbox, ARCA on Container Instances | Rarely. It's what the app tier stands on |
| `platform` | Public load balancer and the VM Scale Set running the Node app | With every infrastructure configuration the TP measures |

```text
foundation ◀── platform      (platform reads foundation's outputs)
```

`platform` reads `foundation` through `terraform_remote_state`, and **only its outputs**.
`foundation/outputs.tf` is therefore a contract: renaming or removing an output breaks
`platform`'s plan.

Unlike in a long-lived project, `foundation` is not permanent: everything is destroyed
at the end of the TP, and the jumpbox and ARCA are billed by the hour while they exist.
A `data` stack (Redis) will sit between the two when storage is added.

## Order

- **Apply** `foundation`, then `platform`. `platform` can't be planned before
  `foundation` has a state.
- **Destroy** `platform`, then `foundation`.

## Commands

The stack is the task's argument. It defaults to `foundation`, except for `destroy`,
which defaults to `platform`.

```sh
mise run infra:plan platform
mise run infra:apply foundation
mise run infra:destroy platform
mise run infra:validate        # every stack
mise run infra:lint            # fmt check + tflint

mise run up                    # login, apply both stacks, Ansible setup, deploy
mise run down                  # destroy platform, then foundation
```

## Variables

Each stack has its own `terraform.tfvars` (gitignored). Copy `terraform.tfvars.example`
in each stack directory and fill it in:

- `foundation`: `azure_sid`, `dockerhub_username`, `dockerhub_token`
- `platform`: `azure_sid`, `datadog_key`

## State

Local: `terraform.tfstate` next to each stack's files, gitignored. Don't lose it, and
don't commit it: it holds the Docker Hub token and the Datadog key in plain text.
Moving to HCP Terraform means adding a `cloud` block to each stack's `terraform.tf` and
switching `platform`'s `terraform_remote_state` to `backend = "remote"`.

## Generated files

Some resources write files into the repository with `local-exec` provisioners when they
are created. All are gitignored except `node/config.js`, which is tracked and edited in
place:

| File | Written by | Read by |
|---|---|---|
| `node/config.js` (`arcaUri`) | `foundation` → `arca` | the Node app |
| `ansible/jumpbox_dns` | `foundation` → `jumpbox` | `ansible/update_vmss_inventory.sh` |
| `node/lb_dns` | `platform` → `app` | `perf/run.sh` |
| `ansible/ddog_api_key` | `platform` → `app` | `ansible/vmss_setup.yml` |

Issue #1 tracks replacing them with outputs and Terraform-managed files.
