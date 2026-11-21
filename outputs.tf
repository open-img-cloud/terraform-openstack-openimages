output "image_ids" {
  description = "Glance image UUIDs by artifact key (\"debian-13\", \"alpine-linux/uefi\")."
  value       = { for k, img in openstack_images_image_v2.this : k => img.id }
}

output "names" {
  description = "Glance image names by artifact key."
  value       = { for k, img in openstack_images_image_v2.this : k => img.name }
}

output "versions" {
  description = "Imported catalog version by artifact key (the oic_version property)."
  value       = { for k, a in local.artifacts : k => a.version }
}

output "sha256" {
  description = "sha256 of the qcow2 by artifact key (the oic_sha256 property, covered by the cosign signature)."
  value       = { for k, a in local.artifacts : k => a.sha256 }
}

output "images" {
  description = "Everything known about each imported artifact, by artifact key."
  value = {
    for k, a in local.artifacts : k => {
      id      = openstack_images_image_v2.this[k].id
      name    = openstack_images_image_v2.this[k].name
      oic_id  = a.oic_id
      variant = a.variant
      version = a.version
      sha256  = a.sha256
      sha512  = a.sha512
      url     = a.url
    }
  }
}

output "index_generated_at" {
  description = "generated_at of the catalog index that was read."
  value       = local.index.generated_at
}

output "support" {
  description = "Upstream support of each requested image (endoflife.date, from the index): release, security_until, is_eol, eol_soon, source; null when the index has none."
  value       = local.support
}

output "end_of_life" {
  description = "Images past or within six months of their upstream end of life, one message each. Empty when there is nothing to plan."
  value       = local.eol_warnings
}
