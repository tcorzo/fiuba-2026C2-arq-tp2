# Infrastructure setup: credentials

What each member needs on their machine before running `mise run up` or any `infra:*`,
`ansible:*` or `perf:*` task. None of these files or values is ever committed: the
repository is public.

## Summary

| # | Credential | Where to get it | Where it goes | Used by |
|---|---|---|---|---|
| 1 | HCP Terraform user token | app.terraform.io → Account settings → Tokens | `mise.local.toml` (or `terraform login`) | Every `terraform` command |
| 2 | Azure login | Your account in the `ARQUI-TP2-ADMIN` group | `az login` session | `ansible/update_vmss_inventory.sh`, the evidence |
| 3 | SSH private key | Shared within the team | `key.pem` at the repository root | Ansible, through the jumpbox |
| 4 | Datadog API key | Datadog → Organization Settings → API Keys | `DATADOG_API_KEY` and `DATADOG_SITE` in `mise.local.toml` | Ansible (agent), Artillery |

Terraform does not use your local Azure session: the HCP Terraform runs authenticate to
Azure on their own (OIDC). You don't need the Azure subscription ID, the Docker Hub
token or any `terraform.tfvars` to run the `prd` stacks. Those are only for the
bootstrap (see the last section).

## 1. HCP Terraform token

1. Accept the invitation to the organization `gaudi-followers` (email from HCP
   Terraform). Without it, the token can't see the workspaces.
2. Go to app.terraform.io → your avatar → **Account settings** → **Tokens** →
   **Create an API token**. Use a **user token**: an organization token can't start
   runs.
3. Put it in `mise.local.toml` at the repository root (gitignored). This scopes the
   token to this repository and doesn't touch other HCP accounts you are logged into:

   ```toml
   [env]
   TF_TOKEN_app_terraform_io = "<your token>"
   TFE_TOKEN = "{{env.TF_TOKEN_app_terraform_io}}"
   ```

   Alternative: `terraform login`, which stores the token globally in
   `~/.terraform.d/credentials.tfrc.json`. If both exist, the variable wins.

Check: `mise run infra:init foundation` ends with "HCP Terraform has been successfully
initialized".

## 2. Azure login

Your account must be a member of the Entra ID group `ARQUI-TP2-ADMIN` (Contributor on
`RG-PRODUCTION`).

```sh
az login        # az is installed by `mise install`
```

`mise run up` runs it for you. Check:
`az group show -n RG-PRODUCTION --query name -o tsv` prints `RG-PRODUCTION`.

## 3. SSH key (`key.pem`)

The private key of the Azure SSH key `ssh_key` in `RG-PRODUCTION`. Azure shows it only
once, when the key is created, so it is passed within the team by a private channel,
never through the repository.

```sh
cp <downloaded file> key.pem    # repository root
chmod 400 key.pem
```

`*.pem` is gitignored and excluded from the HCP Terraform uploads.

## 4. Datadog API key

Datadog → **Organization Settings** → **API Keys** → copy or create a key. Use an
**API key** (32 hex characters), not an application key (`ddapp_…`): the agent and
Artillery reject the latter. Add it to the same `mise.local.toml`:

```toml
[env]
DATADOG_API_KEY = "<your key>"
DATADOG_SITE = "<your site>"
```

Or export both in the shell before each session. `mise run up`, `ansible:setup` and
`perf:run` stop if either is missing.

`DATADOG_SITE` is the host in your browser's URL without the `app.` prefix:
`datadoghq.com` for `app.datadoghq.com`, `us5.datadoghq.com`, `datadoghq.eu`, and so
on. It has no default on purpose: a key belongs to one site, and the agent or Artillery
sending it to another one loses the data without a visible error.
`ansible/vmss_setup.yml` passes it to the agent, and Artillery's Datadog plugin reads it
from the environment.

## Run

```sh
mise trust && mise install      # once per clone
mise run up                     # applies foundation and platform, sets up and deploys the app
```

## Bootstrap only (subscription Owner, once per group)

Already applied. Needed again only to recreate the workspaces, rotate a workspace
secret, or change the Azure identity. See `infra/bootstrap/README.md`.

| Credential | Where to get it | Where it goes |
|---|---|---|
| Azure login with **Owner** on the subscription | The subscription's Owner account | `az login` session |
| Azure subscription ID | `az account show --query id -o tsv` | `azure_sid` in `infra/bootstrap/terraform.tfvars` |
| Docker Hub username and a *Public Repo Read-only* access token | hub.docker.com → Account settings → Personal access tokens | `dockerhub_username`, `dockerhub_token` in `infra/bootstrap/terraform.tfvars` |
| HCP Terraform user token that can manage workspaces in `arvault-prd` | Step 1 | `mise.local.toml` |

```sh
cp infra/bootstrap/terraform.tfvars.example infra/bootstrap/terraform.tfvars   # fill it in
mise run infra:bootstrap
```

`infra/bootstrap/terraform.tfstate` is local and gitignored. Keep a backup: it holds no
secrets, but without it the bootstrap can't manage what it created.
