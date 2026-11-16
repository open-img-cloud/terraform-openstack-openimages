# Imports Debian 13, Ubuntu 24.04 and the UEFI variant of Alpine Linux into the current project,
# then boots a server from Debian 13.
#
#   export OS_CLOUD=mycloud   # an entry of clouds.yaml
#   terraform init && terraform apply

terraform {
  required_version = ">= 1.3"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
  }
}

provider "openstack" {}

module "images" {
  source = "../.."
  # From the registry once published:
  # source  = "open-img-cloud/openimages/openstack"
  # version = "~> 0.1"

  images   = ["debian-13", "ubuntu-24.04", "alpine-linux"]
  variants = { "alpine-linux" = ["uefi"] }

  tags = ["openimages"]
}

variable "flavor_name" {
  description = "Flavor of the example server."
  type        = string
  default     = "m1.small"
}

variable "network_name" {
  description = "Network of the example server."
  type        = string
  default     = "private"
}

resource "openstack_compute_instance_v2" "web" {
  name        = "web1"
  flavor_name = var.flavor_name
  image_id    = module.images.image_ids["debian-13"]

  network {
    name = var.network_name
  }

  lifecycle {
    # A new Debian 13 version replaces the Glance image: do not rebuild the server for it.
    ignore_changes = [image_id]
  }
}

output "image_ids" {
  value = module.images.image_ids
}

output "versions" {
  value = module.images.versions
}
