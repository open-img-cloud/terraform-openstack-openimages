terraform {
  # Lifecycle postconditions need Terraform 1.2; 1.3 is the oldest release tested in CI.
  # OpenTofu 1.6 and newer work too.
  required_version = ">= 1.3"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}
