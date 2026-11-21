# Reads the openimages.cloud catalog index (schema oic-index/v1) and creates one Glance image per
# selected artifact, with the Glance properties of the index and the oic_* keys that oic-sync
# sets, so that both tools recognise the same images.

data "http" "index" {
  count = var.index_json == null ? 1 : 0

  url = var.index_url
  request_headers = {
    Accept = "application/json"
  }

  retry {
    attempts     = 3
    min_delay_ms = 1000
    max_delay_ms = 10000
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Cannot fetch the catalog index ${var.index_url}: HTTP ${self.status_code}."
    }
    postcondition {
      condition     = try(jsondecode(self.response_body).schema, "") == "oic-index/v1"
      error_message = "${var.index_url} is not an oic-index/v1 catalog index."
    }
    postcondition {
      condition = alltrue([
        for id in var.images : contains(try([for img in jsondecode(self.response_body).images : img.id], []), id)
      ])
      error_message = "Unknown image id in var.images. The catalog index lists: ${join(", ", try([for img in jsondecode(self.response_body).images : img.id], []))}."
    }
  }
}

locals {
  index   = jsondecode(var.index_json != null ? var.index_json : data.http.index[0].response_body)
  catalog = { for img in local.index.images : img.id => img }

  # Upstream support of each requested image (endoflife.date dates published in the index; null
  # when the index has none). An image id missing from the index is reported by data.http.index.
  support = {
    for id in distinct(var.images) : id => try({
      release        = tostring(local.catalog[id].support.release)
      security_until = try(tostring(local.catalog[id].support.security_until), null)
      is_eol         = try(local.catalog[id].support.is_eol == true, false)
      eol_soon       = try(local.catalog[id].support.eol_soon == true && local.catalog[id].support.is_eol != true, false)
      source         = try(tostring(local.catalog[id].support.source), null)
    }, null)
  }
  eol_ids = [for id, s in local.support : id if try(s.is_eol, false)]
  eol_warnings = [
    for id, s in local.support :
    "${id}: release ${s.release} ${s.is_eol ? "reached its upstream end of life on" : "reaches its upstream end of life on"} ${coalesce(s.security_until, "an unknown date")}"
    if try(s.is_eol || s.eol_soon, false)
  ]
  # var.eol = "skip": images past their end of life are left out.
  selected = [for id in distinct(var.images) : id if !(var.eol == "skip" && contains(local.eol_ids, id))]

  # One entry per artifact to import, keyed like oic-sync labels: "debian-13", "alpine-linux/uefi".
  # An image id missing from the index fails here ("The given key does not identify an element").
  artifacts = merge([
    for id in local.selected : {
      for a in local.catalog[id].artifacts :
      (a.variant == null ? id : "${id}/${a.variant}") => {
        oic_id  = id
        variant = a.variant
        version = a.version
        url     = a.url
        format  = a.format
        sha256  = lower(a.sha256)
        sha512  = try(lower(a.sha512), null)
        size    = try(a.size, null)
        digests = {
          for k, v in { sha256 = a.sha256, sha512 = try(a.sha512, null) } : k => lower(v) if v != null
        }
        min_disk_gb = try(ceil(a.virtual_size / 1073741824), 0)
        # Same stable name as oic-sync: the catalog title, plus the variant when there are several.
        name = lookup(
          var.names,
          a.variant == null ? id : "${id}/${a.variant}",
          format(
            "%s%s",
            var.name_prefix,
            a.variant != null && length(local.catalog[id].artifacts) > 1
            ? "${local.catalog[id].title} (${upper(a.variant)})"
            : local.catalog[id].title,
          ),
        )
        # Precedence as in oic-sync: optional set, index set, extra properties, oic_* keys.
        properties = {
          for k, v in merge(
            { for k, v in try(local.catalog[id].optional_glance_properties, {}) : k => v if var.with_optional_properties },
            a.glance_properties,
            var.properties,
            { oic_id = id, oic_version = a.version, oic_sha256 = lower(a.sha256) },
            { for k, v in { oic_variant = a.variant } : k => v if v != null },
          ) : k => tostring(v)
        }
      }
      if a.arch == var.architecture && (
        a.variant == null || !contains(keys(var.variants), id) || contains(lookup(var.variants, id, []), a.variant)
      )
    }
  ]...)
}

resource "openstack_images_image_v2" "this" {
  for_each = local.artifacts

  name             = each.value.name
  region           = var.region
  container_format = "bare"
  disk_format      = each.value.format
  min_disk_gb      = each.value.min_disk_gb
  visibility       = var.visibility
  hidden           = var.hidden
  protected        = var.protected
  tags             = var.tags
  properties       = each.value.properties

  # A new version in the index changes the URL: the image is replaced.
  image_source_url = each.value.url
  # web_download conflicts with verify_checksum: set only one of them.
  web_download     = var.web_download ? true : null
  verify_checksum  = var.web_download ? null : true
  image_cache_path = var.web_download ? null : var.image_cache_path

  timeouts {
    create = "60m"
  }

  lifecycle {
    # Create the new version before deleting the old one.
    create_before_destroy = true

    precondition {
      condition     = var.eol != "fail" || !contains(local.eol_ids, each.value.oic_id)
      error_message = "${each.value.oic_id} is past its upstream end of life (eol = \"fail\"): ${join("; ", local.eol_warnings)}. Set eol = \"warn\" to import it anyway or \"skip\" to leave it out."
    }

    # self.status is unknown until the image exists: both checks run once the image is active.
    postcondition {
      condition     = self.status != "active" || (each.value.size == null ? self.size_bytes > 0 : self.size_bytes == each.value.size)
      error_message = "Glance stored ${self.size_bytes} bytes for ${each.key}, the index says ${coalesce(each.value.size, -1)}."
    }
    postcondition {
      condition = self.status != "active" || (
        lookup(each.value.digests, lookup(self.properties, "os_hash_algo", ""), null) != null
        ? lower(lookup(self.properties, "os_hash_value", "")) == lookup(each.value.digests, lookup(self.properties, "os_hash_algo", ""), "")
        : !var.require_glance_hash
      )
      error_message = "The digest Glance computed for ${each.key} (${lookup(self.properties, "os_hash_algo", "none")}) does not match the catalog index, or Glance reports no sha256/sha512 multihash. Delete this image (terraform apply -replace or destroy) before using it."
    }
  }
}
