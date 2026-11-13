# `bootstrap` stack

What HCP Terraform needs before the `prd` stacks can run remotely. One member applies it
once; everyone else only runs `terraform login`.

| Creates | Why |
|---|---|
| Workspaces `arvault-prd-foundation`, `arvault-prd-platform` and `arvault-prd-observability` in project `arvault-prd` | One state per stack. Remote execution, Terraform 1.17.1, and `infra/envs/prd/<stack>` as working directory, so the CLI uploads the repository root and the stacks can reach `infra/modules` |
| Remote state sharing: `foundation` → `platform` only | `platform` reads `foundation`'s outputs through `terraform_remote_state` |
| Entra ID application + service principal `hcp-terraform-arvault-prd` | The identity the runs act as. It has no secret |
| 4 federated identity credentials | One per Azure workspace (`foundation`, `platform`) and run phase (plan, apply). `observability` only talks to Datadog and gets none. Entra ID trusts tokens HCP Terraform signs for exactly those subjects |
| `Contributor` on the subscription | `foundation` creates the resource group |
| Resource group `RG-PRODUCTION` (`eastus`) | Where the prd stacks deploy. Here, not in `foundation`, so a prd `destroy` keeps it and the team's access |
| `Contributor` on `RG-PRODUCTION` for the Entra ID group `ARQUI-TP2-ADMIN` | The team's access for what isn't Terraform: Ansible's inventory, the evidence (`az vmss list-instances`), the portal |
| Workspace variables | On `foundation` and `platform`: `TFC_AZURE_PROVIDER_AUTH`, `TFC_AZURE_RUN_CLIENT_ID`, `ARM_TENANT_ID` (env); `azure_sid` and, on `foundation` only, `dockerhub_username` / `dockerhub_token` (sensitive). On `observability` only: `DD_API_KEY`, `DD_APP_KEY` (env, sensitive) and `datadog_site` |

Workspace names are unique per organization, so each one is `<project>-<stack>`. The
stack names (`foundation`, `platform`) stay the same from project to project.

The resource group and its role assignment were first created by hand in the portal.
The `import` blocks in `resource_group.tf` adopt them into this stack's state: the first
apply after adding them imports both and changes nothing in Azure. Later applies find
them in state and the blocks do nothing.

## Before applying

- The organization `gaudi-followers` and the project `arvault-prd` exist.
- `terraform login` with an account that can manage workspaces in that project.
- `az login` with an account that can register applications in the tenant and has
  **Owner** on the subscription. Contributor is not enough: it can't assign roles. A
  role on a single resource group is not enough either: `foundation` creates its own
  resource group. Check with:

  ```sh
  az role assignment list --assignee "$(az ad signed-in-user show --query id -o tsv)" \
    --all --include-groups --include-inherited -o table
  ```
- `cp terraform.tfvars.example terraform.tfvars` and fill it in.

```sh
mise run infra:bootstrap
```

## State

Local, `terraform.tfstate` next to this file, gitignored: the workspaces it creates
can't hold the state that creates them. The secrets are sent as write-only values
(`value_wo`), so the state holds no token, only IDs. Keep it on the machine that
applied it.

To change a secret (a rotated Docker Hub token, say), edit `terraform.tfvars` and apply
again, or change the variable in the HCP Terraform UI.

A `terraform.tfvars` written before the `observability` workspace existed lacks
`datadog_api_key`, `datadog_app_key` and `datadog_site`: add them from
`terraform.tfvars.example` before applying again.

## Destroying

`terraform destroy` here deletes the workspaces **and the state in them**, the resource
group `RG-PRODUCTION` and the team's access to it. Destroy the `prd` stacks first
(`mise run down`), and only at the end of the TP.
