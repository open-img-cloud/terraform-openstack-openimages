# terraform test (Terraform 1.9 or newer): no cloud and no network. The OpenStack and HTTP
# providers are mocked and the index is a frozen extract (tests/fixtures/index.json).

mock_provider "openstack" {}
mock_provider "http" {}

variables {
  index_json = file("tests/fixtures/index.json")
}

run "selection_names_and_properties" {
  command = plan

  variables {
    images   = ["debian-13", "alpine-linux"]
    variants = { "alpine-linux" = ["uefi"] }
  }

  assert {
    condition     = toset(keys(output.versions)) == toset(["debian-13", "alpine-linux/uefi"])
    error_message = "Unexpected artifact keys: ${join(", ", keys(output.versions))}"
  }

  assert {
    condition     = openstack_images_image_v2.this["debian-13"].name == "Debian 13"
    error_message = "Stable name must be the catalog title."
  }

  assert {
    condition     = openstack_images_image_v2.this["alpine-linux/uefi"].name == "Alpine Linux (UEFI)"
    error_message = "Multi-variant images take the variant in their name, like oic-sync."
  }

  assert {
    condition = (
      openstack_images_image_v2.this["debian-13"].properties["oic_id"] == "debian-13" &&
      openstack_images_image_v2.this["debian-13"].properties["oic_version"] == "13-20261111-2659" &&
      openstack_images_image_v2.this["debian-13"].properties["oic_sha256"] == "6706a0cddad28e3184586d3043949f9ce1223e7fc53ae8425993ae1d822a0822" &&
      openstack_images_image_v2.this["debian-13"].properties["os_distro"] == "debian" &&
      openstack_images_image_v2.this["debian-13"].properties["hw_qemu_guest_agent"] == "yes" &&
      !contains(keys(openstack_images_image_v2.this["debian-13"].properties), "oic_variant") &&
      !contains(keys(openstack_images_image_v2.this["debian-13"].properties), "hw_rng_model")
    )
    error_message = "Wrong Glance properties for debian-13."
  }

  assert {
    condition = (
      openstack_images_image_v2.this["alpine-linux/uefi"].properties["oic_variant"] == "uefi" &&
      openstack_images_image_v2.this["alpine-linux/uefi"].properties["hw_firmware_type"] == "uefi" &&
      openstack_images_image_v2.this["alpine-linux/uefi"].properties["hw_machine_type"] == "q35"
    )
    error_message = "Wrong Glance properties for alpine-linux/uefi."
  }

  assert {
    condition     = openstack_images_image_v2.this["debian-13"].min_disk_gb == 3 && openstack_images_image_v2.this["alpine-linux/uefi"].min_disk_gb == 1
    error_message = "min_disk_gb must be the virtual size rounded up to GiB."
  }

  assert {
    condition = (
      openstack_images_image_v2.this["debian-13"].verify_checksum == true &&
      openstack_images_image_v2.this["debian-13"].web_download == null &&
      openstack_images_image_v2.this["debian-13"].container_format == "bare" &&
      openstack_images_image_v2.this["debian-13"].disk_format == "qcow2" &&
      openstack_images_image_v2.this["debian-13"].visibility == "private"
    )
    error_message = "Wrong upload settings."
  }
}

run "all_variants_by_default" {
  command = plan

  variables {
    images = ["alpine-linux"]
  }

  assert {
    condition     = toset(keys(output.versions)) == toset(["alpine-linux/bios", "alpine-linux/uefi"])
    error_message = "Every variant must be imported when var.variants does not name the image."
  }
}

run "names_options_and_web_download" {
  command = plan

  variables {
    images                   = ["debian-13", "alpine-linux"]
    name_prefix              = "oic/"
    names                    = { "alpine-linux/bios" = "alpine" }
    properties               = { hw_vif_multiqueue_enabled = "false", site = "gva" }
    with_optional_properties = true
    web_download             = true
    visibility               = "public"
  }

  assert {
    condition     = openstack_images_image_v2.this["debian-13"].name == "oic/Debian 13" && openstack_images_image_v2.this["alpine-linux/bios"].name == "alpine"
    error_message = "name_prefix or names not applied."
  }

  assert {
    condition = (
      openstack_images_image_v2.this["debian-13"].properties["hw_vif_multiqueue_enabled"] == "false" &&
      openstack_images_image_v2.this["debian-13"].properties["site"] == "gva" &&
      openstack_images_image_v2.this["debian-13"].properties["hw_rng_model"] == "virtio"
    )
    error_message = "Extra or optional properties not applied."
  }

  assert {
    condition     = openstack_images_image_v2.this["debian-13"].web_download == true && openstack_images_image_v2.this["debian-13"].verify_checksum == null
    error_message = "web_download must replace verify_checksum."
  }
}

run "reserved_properties_rejected" {
  command = plan

  variables {
    images     = ["debian-13"]
    properties = { oic_version = "1" }
  }

  expect_failures = [var.properties]
}

run "unknown_image_rejected" {
  command = plan

  variables {
    images     = ["debian-13", "no-such-image"]
    index_json = null
    index_url  = "https://mirror.example/index.json"
  }

  override_data {
    target = data.http.index[0]
    values = {
      status_code   = 200
      response_body = file("tests/fixtures/index.json")
    }
  }

  expect_failures = [data.http.index[0]]
}

# The fixture marks debian-13 as past its end of life (fictional) to exercise var.eol.
run "eol_warn_imports_and_reports" {
  command = plan

  variables {
    images = ["debian-13", "alpine-linux"]
  }

  assert {
    condition     = contains(keys(output.versions), "debian-13")
    error_message = "eol = warn must keep debian-13."
  }

  assert {
    condition     = output.end_of_life == ["debian-13: release 13 reached its upstream end of life on 2026-06-30"]
    error_message = "end_of_life must list debian-13 only."
  }

  assert {
    condition     = output.support["alpine-linux"].release == "3.24" && output.support["debian-13"].is_eol
    error_message = "support must carry the index dates."
  }
}

run "eol_skip_leaves_out" {
  command = plan

  variables {
    images = ["debian-13", "alpine-linux"]
    eol    = "skip"
  }

  assert {
    condition     = !contains(keys(output.versions), "debian-13") && contains(keys(output.versions), "alpine-linux/uefi")
    error_message = "eol = skip must leave debian-13 out and keep alpine-linux."
  }
}

run "eol_fail_stops" {
  command = plan

  variables {
    images = ["debian-13"]
    eol    = "fail"
  }

  expect_failures = [openstack_images_image_v2.this]
}

run "eol_invalid_value" {
  command = plan

  variables {
    images = ["debian-13"]
    eol    = "ignore"
  }

  expect_failures = [var.eol]
}

# Mocks cannot return the server-side properties (os_hash_algo, os_hash_value) that a real Glance
# adds: the digest comparison itself is only exercised against a real cloud. These runs check
# that the postconditions are wired: no multihash fails by default, a wrong size always fails.

run "apply_without_glance_multihash_fails" {
  variables {
    images = ["debian-13"]
  }

  override_resource {
    target = openstack_images_image_v2.this["debian-13"]
    values = {
      status     = "active"
      size_bytes = 278593536
    }
  }

  expect_failures = [openstack_images_image_v2.this]
}

run "apply_without_glance_multihash_allowed" {
  variables {
    images              = ["debian-13"]
    require_glance_hash = false
  }

  override_resource {
    target = openstack_images_image_v2.this["debian-13"]
    values = {
      status     = "active"
      size_bytes = 278593536
    }
  }

  assert {
    condition     = output.sha256["debian-13"] == "6706a0cddad28e3184586d3043949f9ce1223e7fc53ae8425993ae1d822a0822"
    error_message = "sha256 output is wrong."
  }
}

run "apply_rejects_wrong_size" {
  # Fresh state: the image of the previous run would otherwise be kept as is.
  state_key = "wrong_size"

  variables {
    images              = ["debian-13"]
    require_glance_hash = false
  }

  override_resource {
    target = openstack_images_image_v2.this["debian-13"]
    values = {
      status     = "active"
      size_bytes = 1
    }
  }

  expect_failures = [openstack_images_image_v2.this]
}
