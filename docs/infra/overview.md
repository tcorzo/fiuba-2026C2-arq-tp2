# Infrastructure overview

This document describes the Azure infrastructure in `infra/` (stacks in `infra/envs/prd/`, modules in `infra/modules/`), how the pieces connect, and how Terraform and Ansible hand off to each other. It describes the baseline the course provides, before any group changes (Redis, scaling, etc.).

## At a glance

| Concern | What it is |
|---|---|
| Cloud / region | Azure, `eastus2` (`var.region`) |
| Entry point | Public **Standard Load Balancer**, port 80 → port 3000 on the VMSS |
| App tier | **Linux VM Scale Set** `tp2vmss`, 1 × `Standard_F1als_v7` (1 vCPU, 2 GiB, no CPU credits), Ubuntu 24.04, Node 24 + pm2 |
| External dependency | **ARCA** mock, `arqsoft/arca:1.0.0` on **Azure Container Instances**, private IP, port 8080 |
| Admin access | **Jumpbox** VM with a public IP. It is the only SSH entry point into the VNet |
| Observability | Datadog agent on every VMSS instance (installed by Ansible) |
| Storage | **None yet.** The TP asks for Redis or another managed (PaaS) database. We chose **Azure Database for PostgreSQL Flexible Server**, so the service keeps tp1's Postgres repositories (H-09) |

## Resource inventory

21 managed resources and 2 data sources, all in the pre-existing resource group `RG-PRODUCTION`, split into two stacks under `infra/envs/prd/` (see its [README](../../infra/envs/prd/README.md)). Each stack calls modules from `infra/modules/`.

`infra/bootstrap`, which the subscription's Owner applies, manages the resource group and the team's access to it (group `ARQUI-TP2-ADMIN`, Contributor). Both were first created in the portal and adopted with `import` blocks. The prd stacks only read the resource group: if `foundation` created it, every `destroy` would delete the team's role assignment with it. The resource group's own region is `eastus`. Every resource is created in `var.region` (`eastus2`), which may differ.

| Stack → module | Terraform address (in the stack) | Azure resource | Notes |
|---|---|---|---|
| `foundation` | `data.azurerm_resource_group.this` | *(data source)* | Reads `RG-PRODUCTION` (`var.resource_group_name`). Everything below lives there. It is **not** managed here |
| `foundation` | `data.azurerm_ssh_public_key.this` | *(data source)* | Reads the pre-existing SSH key `ssh_key` from `RG-PRODUCTION`. It is **not** managed here |
| `foundation` → `network` | `module.network.azurerm_virtual_network.this` | VNet `10.0.0.0/16` | |
| | `module.network.azurerm_subnet.vmss` | Subnet `10.0.2.0/24` | App instances |
| | `module.network.azurerm_subnet.jumpbox` | Subnet `10.0.3.0/24` | Jumpbox |
| | `module.network.azurerm_subnet.container` | Subnet `10.0.4.0/24` | Delegated to `Microsoft.ContainerInstance/containerGroups` |
| | `module.network.azurerm_subnet_network_security_group_association.vmss` | NSG ↔ subnet | Attaches `vmss_http_sg` to the VMSS subnet |
| | `module.network.azurerm_network_security_group.ssh` | NSG `ssh_sg` | Allows TCP 22 from `*` |
| | `module.network.azurerm_network_security_group.vmss_http` | NSG `vmss_http_sg` | Allows TCP 3000 from `*` |
| `foundation` → `jumpbox` | `module.jumpbox.random_string.dns_label` | — | DNS label |
| | `module.jumpbox.azurerm_public_ip.this` | Public IP (Standard, static) | `<random>.eastus2.cloudapp.azure.com` |
| | `module.jumpbox.azurerm_network_interface.this` | NIC | |
| | `module.jumpbox.azurerm_network_interface_security_group_association.this` | NSG ↔ NIC | Attaches `ssh_sg` to the jumpbox NIC |
| | `module.jumpbox.azurerm_linux_virtual_machine.this` | VM `jumpbox` | `Standard_F1als_v7`, `Standard_LRS` disk |
| `foundation` → `arca` | `module.arca.random_string.name` | — | Container group name |
| | `module.arca.azurerm_container_group.this` | Container Instances group | 0.5 vCPU / 0.5 GiB, private IP, `restart_policy = Always` |
| `platform` → `app` | `module.app.azurerm_linux_virtual_machine_scale_set.this` | VMSS `tp2vmss` | `instances = 1` (hard-coded), `upgrade_mode = Automatic`, `StandardSSD_LRS` |
| | `module.app.random_string.lb_dns_label` | — | DNS label |
| | `module.app.azurerm_public_ip.lb` | Public IP (Standard, static) | The public URL of the service |
| | `module.app.azurerm_lb.this` | Load Balancer `tp2_lb` (Standard) | |
| | `module.app.azurerm_lb_backend_address_pool.this` | Backend pool | VMSS NICs join it |
| | `module.app.azurerm_lb_probe.this` | Health probe | TCP on port 3000 |
| | `module.app.azurerm_lb_rule.http` | LB rule `HTTPFwd` | TCP 80 → 3000 |

Providers (each stack's `terraform.tf`): `azurerm ~>4.80` and `random ~>3.0`. State and runs live in HCP Terraform (organization `gaudi-followers`, project `arvault-prd`, one workspace per stack). `infra/bootstrap` creates the workspaces and the Azure identity the remote runs use. See the prd [README](../../infra/envs/prd/README.md).

### VM size

Every VM (the jumpbox and each VMSS instance) is `Standard_F1als_v7`: 1 vCPU, 2 GiB, AMD.
The B series (`Standard_B1s`, the course's default) is not offered to our subscription
in `eastus2`: `az vm list-skus -l eastus2` lists every B size as
`NotAvailableForSubscription`, and the first apply failed with `SkuNotAvailable`. The
smallest unrestricted sizes there are the v7 generation.

- **1 vCPU, on purpose.** The subscription allows 4 regional vCPUs (`az vm list-usage
  -l eastus2`). The jumpbox plus 2 VMSS instances fit; a 2-vCPU size wouldn't.
- **No CPU credits.** Unlike the B series, an F-series VM doesn't throttle to a
  baseline when it runs out of credits, so a long load test measures the same CPU from
  start to end.
- **NVMe and Gen2 only.** The image (Ubuntu 24.04 `server`) is Gen2 and NVMe-capable.
  The OS disk controller type is not set, so Azure chooses it; this size only offers
  NVMe. (`azurerm_linux_virtual_machine_scale_set` has no `disk_controller_type`.)
- **Cost.** About USD 0.06/h per VM in `eastus2` (B1s: USD 0.01/h). Run `mise run down`
  when not working.

## Network topology

```mermaid
flowchart LR
    user([Load generator / client<br/>outside Azure])
    admin([Operator<br/>Terraform + Ansible])
    dd[(Datadog SaaS)]
    hub[(Docker Hub)]

    subgraph rg["Resource group RG-PRODUCTION (resources in eastus2)"]
        lbpip[Public IP<br/>lb_public_ip]
        lb[Standard Load Balancer<br/>tp2_lb<br/>rule: TCP 80 → 3000<br/>probe: TCP 3000]
        jbpip[Public IP<br/>jumpbox_public_ip]

        subgraph vnet["VNet tp2_network 10.0.0.0/16"]
            subgraph snvmss["tp2_vmss_subnet 10.0.2.0/24<br/>NSG vmss_http_sg: allow 3000"]
                vm1[VMSS instance<br/>Node app :3000<br/>pm2 + Datadog agent]
                vmN[...more instances<br/>when scaled]
            end
            subgraph snjb["tp2_jumpbox_subnet 10.0.3.0/24"]
                jb[Jumpbox VM<br/>NIC NSG ssh_sg: allow 22]
            end
            subgraph snaci["tp2_container_subnet 10.0.4.0/24<br/>delegated to ACI"]
                arca[ARCA container<br/>arqsoft/arca:1.0.0 :8080]
            end
        end
    end

    user -- "HTTP :80" --> lbpip --> lb
    lb -- ":3000" --> vm1
    lb -.-> vmN
    vm1 -- "POST /validar :8080" --> arca
    admin -- "SSH :22" --> jbpip --> jb
    jb -- "SSH :22 (ProxyCommand)" --> vm1
    vm1 -- "metrics" --> dd
    hub -. "image pull" .-> arca
```

Things to note about the topology:

- **VMSS instances have no public IP.** Inbound traffic from the internet arrives only through the load balancer. Outbound traffic (apt, NodeSource, npm, Datadog) leaves through the LB frontend IP, because a load-balancing rule gives the backend pool outbound SNAT by default.
- **SSH reaches the instances only through the jumpbox.** Azure's default `AllowVnetInBound` NSG rule lets the jumpbox reach the VMSS subnet on port 22. `ansible/update_vmss_inventory.sh` writes the matching `ProxyCommand` into the Ansible inventory.
- **ARCA is only reachable inside the VNet.** Its subnet has no NSG, so only Azure's default rules apply: traffic from inside the VNet is allowed, traffic from the internet is denied.
- **No NSG restricts sources.** `ssh_sg` and `vmss_http_sg` both allow `*`. Because the VMSS has no public IP, the only internet path to port 3000 is the LB. The jumpbox, however, accepts SSH from the entire internet.

## Request path

```mermaid
sequenceDiagram
    autonumber
    participant C as Client (Artillery)
    participant LB as Azure Standard LB
    participant N as Node app (VMSS instance)
    participant A as ARCA (ACI)

    C->>LB: GET http://<lb_dns>/<dni>
    LB->>N: forward to :3000 (healthy backend chosen by 5-tuple hash)
    N->>A: POST http://<aci-private-ip>:8080/validar {dni}
    A-->>N: 200 + body
    N-->>LB: 200 + body (or 500 on error)
    LB-->>C: response
```

This is the path of the course's example app, which `node/` no longer holds: it now holds tp1's exchange service (`node/server.js`), which does not call ARCA yet. The `dni` → `/validar` step comes back with the ARCA integration.

`GET /` returns `Server is up.` without calling ARCA. The TP asks you to use it to measure baseline latency.

The probe is **TCP-only**. The LB marks an instance healthy as soon as something is listening on port 3000, even if the app cannot reach ARCA or its storage.

## Provisioning pipeline

`mise run up` runs everything in this order. Terraform and Ansible do not share state directly, and Terraform writes nothing to disk. The scripts read the outputs they need from HCP Terraform with `infra/output.sh` (`terraform output`).

```mermaid
flowchart TD
    boot[mise run infra:bootstrap<br/>once per group: workspaces,<br/>variables, Azure OIDC identity]
    start[mise run up]
    login[az login<br/>for az vmss nic list]
    applyf[terraform apply foundation<br/>remote run in arvault-prd-foundation]
    apply[terraform apply platform<br/>remote run in arvault-prd-platform]

    boot -.-> start
    start --> login --> applyf --> apply

    subgraph outputs["Outputs in HCP Terraform"]
        jb[foundation: jumpbox_fqdn]
        arca[foundation: arca_uri]
        lbo[platform: lb_fqdn]
        appcfg[platform: app_config<br/>arcaUri]
    end

    applyf --> jb & arca
    apply --> lbo & appcfg
    arca --> appcfg

    setup[mise run ansible:setup<br/>ansible/setup.sh]
    inv[ansible/update_vmss_inventory.sh<br/>az vmss nic list → vmss_hosts]
    pbsetup[vmss_setup.yml<br/>Datadog agent, unzip, Node 24, pm2]
    ddkey[/DATADOG_API_KEY<br/>environment variable/]
    deploy[mise run app:deploy<br/>ansible/deploy.sh]
    cfg[node/config.local.json<br/>gitignored]
    zip[node/zip → node/src.zip]
    pbdeploy[vmss_deploy.yml<br/>unzip, npm ci, pm2 start server.js]

    apply --> setup --> inv --> pbsetup
    jb --> inv
    ddkey --> pbsetup
    pbsetup --> deploy --> cfg --> zip --> pbdeploy
    appcfg --> cfg

    perf[mise run perf:run → perf/run.sh → Artillery]
    lbo --> perf
    ddkey --> perf
```

Some consequences of this design:

- **No tracked file changes on `apply`.** `node/config.js` reads `node/config.local.json`, which `ansible/deploy.sh` writes from `app_config` on every deploy. Environment variables override it and it has defaults, so the app also starts locally without it.
- **Outputs can't go stale on disk.** Every script reads the latest applied state when it runs. `app_config` is computed by `platform` from `foundation`'s outputs, so apply `platform` after any `foundation` change.
- **The VMSS instance count is set in two places.** Terraform's `instances` sets the count, but Ansible configures whatever `az vmss nic list` returns. Re-run `mise run ansible:setup` and `mise run app:deploy` after scaling (the README says so too).
- **The VMSS has no custom image or cloud-init.** If Azure replaces an instance (automatic upgrade or autoscale), the new instance boots without Node or the app until Ansible runs again. This matters for any autoscaling design.
- **Where secrets live.** The Docker Hub token is a sensitive workspace variable, and HCP Terraform's state (encrypted at rest) holds it in plain text. The bootstrap stack's local state holds it too. The Datadog key never reaches Terraform: it lives in `DATADOG_API_KEY`. Keep `terraform output` and run logs out of evidence files unless you read them first.

## What the TP will change

According to the assignment (`README.md`), groups will typically:

1. **Add a managed storage resource**, for example `azurerm_managed_redis`, and wire its connection data into the app the same way ARCA's URI is wired (a provisioner or generated config). We use `azurerm_postgresql_flexible_server`: the service's `DATABASE_URL` points at it.
2. **Scale the app tier horizontally.** Make `instances` a variable or add autoscale (`azurerm_monitor_autoscale_setting`). Keep in mind the "no bootstrap on new instances" caveat above.
3. **Reconsider tactics that depended on nginx in TP 1**, because the Azure Standard LB is a layer-4 balancer. It has no HTTP caching, no rate limiting, no HTTP-aware health checks, and no request routing.
