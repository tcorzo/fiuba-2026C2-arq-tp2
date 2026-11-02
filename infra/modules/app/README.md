# `app` module

The Node app's tier: a VM Scale Set behind a public Standard Load Balancer.

- **Load balancer** `tp2_lb`: a public IP with a random DNS label, one backend pool, a TCP
  probe on port 3000, and the rule `HTTPFwd` (TCP 80 → 3000).
- **Scale set** `tp2vmss`: 1 instance, `upgrade_mode = Automatic`, `StandardSSD_LRS`
  disk. Its NICs join the backend pool. The image is plain Ubuntu: Ansible installs Node,
  pm2, the Datadog agent and the app afterwards, so a new instance boots empty.

The scale set and the load balancer share a module because the scale set can't join the
pool until the rule exists (`depends_on`), and scaling the TP changes this unit.

The module writes nothing outside Terraform's state. The stack exposes the LB FQDN as the
`lb_fqdn` output, which `perf/run.sh` reads with `terraform output`. The Datadog key never
reaches Terraform: Ansible reads it from `DATADOG_API_KEY`.

## Usage

```hcl
module "app" {
  source = "../../../modules/app"

  resource_group_name = local.foundation.resource_group_name
  location            = local.foundation.location
  subnet_id           = local.foundation.vmss_subnet_id
  ssh_public_key      = local.foundation.ssh_public_key
  vm_size             = var.machine_sku
  image               = local.image
}
```
