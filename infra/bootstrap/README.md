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
- The Datadog credentials of the `observability` workspace exist. See
  [Datadog credentials](#datadog-credentials).
- `cp terraform.tfvars.example terraform.tfvars` and fill it in.

```sh
mise run infra:bootstrap
```

## Datadog credentials

The `observability` stack runs remotely, in HCP Terraform, so it can't read anyone's
local `DATADOG_API_KEY`. Its workspace holds its own pair of keys. Both are dedicated to
it, so revoking them breaks no member's setup and no member's key breaks the stack.

The application key belongs to a **service account**, never to a person. An application
key acts with the permissions of its owner: a member's key would let anyone with access to
the workspace act as that member (as an Admin, for the organization's owner), and the
stack would break when that member revoked it or left the organization.

The team shares one Datadog organization: every member is invited to it and has their own
API key there, for Ansible and Artillery. One organization keeps the agent's metrics,
Artillery's and the dashboard in the same place, whoever ran each step.

Done once, by a Datadog Admin of the organization:

1. **Check the role.** Organization Settings → Roles → *Datadog Standard* must grant
   *Manage Tags for Metrics* (`metric_tags_write`), `metrics_read` and the
   dashboards' read and write permissions. A scope can only narrow what the role grants.
2. **Create the service account.** Organization Settings → Service Accounts → New Service
   Account, named `hcp-terraform-arvault-prd-observability`, with the *Datadog Standard*
   role.
3. **Create its application key.** In the service account → Application Keys → New Key,
   named `hcp-terraform-arvault-prd-observability`, with exactly these scopes:

   | Scope | Used for |
   |---|---|
   | `dashboards_read` | Reading the dashboard on every plan |
   | `dashboards_write` | Creating, updating and deleting the dashboard |
   | `metrics_read` | Reading the distributions' tag configuration on every plan |
   | `metric_tags_write` | Creating, updating and deleting that tag configuration |

   Datadog shows the key **once**. Copy it straight into `terraform.tfvars`; if it is
   lost, revoke it and create another.
4. **Create a dedicated API key.** Organization Settings → API Keys → New Key, named
   `hcp-terraform-arvault-prd-observability`, like the application key, so the pair reads
   as one.
5. **Fill in `terraform.tfvars`:** `datadog_api_key` and `datadog_app_key` with the two
   keys, `datadog_site` with the same value as `DATADOG_SITE`. Then
   `mise run infra:bootstrap`. They reach the workspace as `DD_API_KEY` and `DD_APP_KEY`,
   sensitive and write-only: they are in neither this stack's state nor its plan.

If the first `mise run infra:plan observability` fails with a 403, the error names the
missing permission: add it to the role or the key's scopes, not a broader key.

To rotate either key: create the new one, put it in `terraform.tfvars`, run
`mise run infra:bootstrap`, then revoke the old one in Datadog. A leaked key is revoked
and replaced, not just deleted from wherever it appeared.

## State

Local, `terraform.tfstate` next to this file, gitignored: the workspaces it creates
can't hold the state that creates them. The secrets are sent as write-only values
(`value_wo`), so the state holds no token, only IDs. Keep it on the machine that
applied it.

To change a secret (a rotated Docker Hub token, say; for the Datadog keys see [Datadog credentials](#datadog-credentials)), edit `terraform.tfvars` and apply
again, or change the variable in the HCP Terraform UI.

A `terraform.tfvars` written before the `observability` workspace existed lacks
`datadog_api_key`, `datadog_app_key` and `datadog_site`: add them from
`terraform.tfvars.example` before applying again.

## Destroying

`terraform destroy` here deletes the workspaces **and the state in them**, the resource
group `RG-PRODUCTION` and the team's access to it. Destroy the `prd` stacks first
(`mise run down`), and only at the end of the TP.
