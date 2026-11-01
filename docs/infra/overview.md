# Infrastructure overview

This document describes the Azure infrastructure in `infra/`, how the pieces connect, and how Terraform and Ansible hand off to each other. It describes the baseline the course provides, before any group changes (Redis, scaling, etc.).

## At a glance

| Concern | What it is |
|---|---|
| Cloud / region | Azure, `eastus2` (`var.region`) |
| Entry point | Public **Standard Load Balancer**, port 80 → port 3000 on the VMSS |
| App tier | **Linux VM Scale Set** `tp2vmss`, 1 × `Standard_B1s` (1 vCPU, 1 GiB), Ubuntu 24.04, Node 24 + pm2 |
| External dependency | **ARCA** mock, `arqsoft/arca:1.0.0` on **Azure Container Instances**, private IP, port 8080 |
| Admin access | **Jumpbox** VM with a public IP. It is the only SSH entry point into the VNet |
| Observability | Datadog agent on every VMSS instance (installed by Ansible) |
| Storage | **None yet.** The TP asks for Redis or another managed (PaaS) database |

## Resource inventory

22 managed resources and 1 data source, all in the resource group `tp2_resource_group`.

| File | Terraform address | Azure resource | Notes |
|---|---|---|---|
| `resource_group.tf` | `azurerm_resource_group.tp2_resource_group` | Resource group | Everything below lives here |
| `ssh.tf` | `data.azurerm_ssh_public_key.ssh_key` | *(data source)* | Reads a pre-existing SSH key from the `keys` RG. It is **not** managed here |
| `network.tf` | `azurerm_virtual_network.tp2_vn` | VNet `10.0.0.0/16` | |
| | `azurerm_subnet.tp2_sn_vmss` | Subnet `10.0.2.0/24` | App instances |
| | `azurerm_subnet.tp2_sn_jumpbox` | Subnet `10.0.3.0/24` | Jumpbox |
| | `azurerm_subnet.tp2_sn_container` | Subnet `10.0.4.0/24` | Delegated to `Microsoft.ContainerInstance/containerGroups` |
| | `azurerm_subnet_network_security_group_association.sn_vmss_nsg_assoc` | NSG ↔ subnet | Attaches `vmss_http_sg` to the VMSS subnet |
| `network_security_groups.tf` | `azurerm_network_security_group.ssh_sg` | NSG | Allows TCP 22 from `*` |
| | `azurerm_network_security_group.vmss_http_sg` | NSG | Allows TCP 3000 from `*` |
| `jumpbox.tf` | `random_string.jumpbox_name` | — | DNS label |
| | `azurerm_public_ip.jumpbox_public_ip` | Public IP (Standard, static) | `<random>.eastus2.cloudapp.azure.com` |
| | `azurerm_network_interface.jumpbox_nic` | NIC | |
| | `azurerm_network_interface_security_group_association.jumpbox_nic_nsg` | NSG ↔ NIC | Attaches `ssh_sg` to the jumpbox NIC |
| | `azurerm_linux_virtual_machine.jumpbox` | VM | `Standard_B1s`, `Standard_LRS` disk |
| `node.tf` | `azurerm_linux_virtual_machine_scale_set.tp2_vmss` | VMSS | `instances = 1` (hard-coded), `upgrade_mode = Automatic`, `StandardSSD_LRS` |
| | `random_string.lb_name` | — | DNS label |
| | `azurerm_public_ip.lb_public_ip` | Public IP (Standard, static) | The public URL of the service |
| | `azurerm_lb.tp2_lb` | Load Balancer (Standard) | |
| | `azurerm_lb_backend_address_pool.lb_backend_address_pool` | Backend pool | VMSS NICs join it |
| | `azurerm_lb_probe.lb_probe` | Health probe | TCP on port 3000 |
| | `azurerm_lb_rule.lb_rule` | LB rule `HTTPFwd` | TCP 80 → 3000 |
| `arca.tf` | `random_string.container_name` | — | Container group name |
| | `azurerm_container_group.tp2_container` | Container Instances group | 0.5 vCPU / 0.5 GiB, private IP, `restart_policy = Always` |

Providers (`versions.tf`): `azurerm ~>4.80`, `random ~>3.0`, and `local ~>2.2`. The `local` provider is declared but nothing uses it. The `local-exec` blocks are provisioners built into Terraform, not part of that provider.

## Network topology

```mermaid
flowchart LR
    user([Load generator / client<br/>outside Azure])
    admin([Operator<br/>Terraform + Ansible])
    dd[(Datadog SaaS)]
    hub[(Docker Hub)]

    subgraph rg["Resource group tp2_resource_group (eastus2)"]
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

`GET /` returns `Server is up.` without calling ARCA. The TP asks you to use it to measure baseline latency.

The probe is **TCP-only**. The LB marks an instance healthy as soon as something is listening on port 3000, even if the app cannot reach ARCA or its storage.

## Provisioning pipeline

`start.sh` runs everything in this order. Terraform and Ansible do not share state directly. Terraform's `local-exec` provisioners write small files into the repo, and the scripts and the app read those files later.

```mermaid
flowchart TD
    tfvars[/infra/terraform.tfvars<br/>azure_sid, datadog_key,<br/>dockerhub_username, dockerhub_token/]
    start[start.sh]
    login[az login]
    apply[terraform -chdir=infra apply]

    start --> login --> apply
    tfvars --> apply

    subgraph files["Files written by local-exec (all gitignored)"]
        cfg[node/config.js<br/>arcaUri = ACI private IP]
        lbdns[node/lb_dns<br/>LB FQDN]
        jbdns[ansible/jumpbox_dns<br/>jumpbox FQDN]
        ddkey[ansible/ddog_api_key<br/>Datadog API key]
    end

    apply --> cfg & lbdns & jbdns & ddkey

    setup[ansible/setup.sh]
    inv[ansible/update_vmss_inventory.sh<br/>az vmss nic list → vmss_hosts]
    pbsetup[vmss_setup.yml<br/>Datadog agent, unzip, Node 24, pm2]
    deploy[ansible/deploy.sh]
    zip[node/zip → node/src.zip]
    pbdeploy[vmss_deploy.yml<br/>unzip, npm install, pm2 start app.js]

    apply --> setup --> inv --> pbsetup
    jbdns --> inv
    ddkey --> pbsetup
    pbsetup --> deploy --> zip --> pbdeploy
    cfg --> zip

    perf[perf/run.sh → Artillery]
    lbdns --> perf
```

Some consequences of this design:

- **`node/config.js` is a tracked file that Terraform edits in place.** Terraform substitutes the ARCA IP with `sed`, leaving a `config.js.bak` behind. Expect a dirty working tree after `apply`, and don't commit the IP.
- **Provisioners run only at creation time.** If ACI gets a new private IP (for example, after the container group is recreated), `config.js` is only updated when Terraform recreates that resource. The same applies to the DNS files.
- **The VMSS instance count is set in two places.** Terraform's `instances` sets the count, but Ansible configures whatever `az vmss nic list` returns. Re-run `ansible/setup.sh` and `ansible/deploy.sh` after scaling (the README says so too).
- **The VMSS has no custom image or cloud-init.** If Azure replaces an instance (automatic upgrade or autoscale), the new instance boots without Node or the app until Ansible runs again. This matters for any autoscaling design.
- **Secrets reach disk.** The Datadog key is written to `ansible/ddog_api_key`, and the Terraform state stores the key and the Docker Hub token in plain text. Both files are gitignored. Keep them out of evidence files.

## What the TP will change

According to the assignment (`README.md`), groups will typically:

1. **Add a managed storage resource**, for example `azurerm_managed_redis`, and wire its connection data into the app the same way ARCA's URI is wired (a provisioner or generated config).
2. **Scale the app tier horizontally.** Make `instances` a variable or add autoscale (`azurerm_monitor_autoscale_setting`). Keep in mind the "no bootstrap on new instances" caveat above.
3. **Reconsider tactics that depended on nginx in TP 1**, because the Azure Standard LB is a layer-4 balancer. It has no HTTP caching, no rate limiting, no HTTP-aware health checks, and no request routing.
