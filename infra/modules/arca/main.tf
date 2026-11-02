# Random name to avoid a container name collision
resource "random_string" "name" {
  length  = 25
  lower   = true
  upper   = false
  special = false
  numeric = false
}

resource "azurerm_container_group" "this" {
  name                = random_string.name.result
  location            = var.location
  resource_group_name = var.resource_group_name
  ip_address_type     = "Private"
  subnet_ids          = [var.subnet_id]
  os_type             = "Linux"
  restart_policy      = "Always"

  container {
    name   = random_string.name.result
    image  = "arqsoft/arca:1.0.0"
    cpu    = 0.5
    memory = 0.5

    ports {
      port     = 8080
      protocol = "TCP"
    }
  }

  # Docker Hub credentials for pulling the image
  image_registry_credential {
    server   = "index.docker.io"
    username = var.dockerhub_username
    password = var.dockerhub_token
  }
}
