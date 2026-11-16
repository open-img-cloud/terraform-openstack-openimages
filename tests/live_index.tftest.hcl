# Reads the live catalog index (network, no cloud): catches a change of the index format that
# would break the module. The OpenStack provider is mocked.

mock_provider "openstack" {}

run "live_index" {
  command = plan

  variables {
    images = ["debian-13", "ubuntu-24.04", "alpine-linux", "alpaquita-linux", "freebsd-15"]
  }

  assert {
    condition     = length(output.versions) == 7
    error_message = "Expected 7 artifacts (alpine-linux and alpaquita-linux have two variants each), got: ${join(", ", keys(output.versions))}"
  }

  assert {
    condition     = alltrue([for k, v in output.sha256 : length(v) == 64])
    error_message = "Every artifact needs a sha256."
  }

  assert {
    condition     = alltrue([for k, img in openstack_images_image_v2.this : img.properties["oic_id"] == split("/", k)[0]])
    error_message = "oic_id must match the artifact key."
  }
}
