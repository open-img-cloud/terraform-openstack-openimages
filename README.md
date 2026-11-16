<p align="center">
  <a href="https://openimages.cloud">
    <img src="https://openimages.cloud/img/og.png" alt="openimages.cloud: signed, boot-tested cloud images for OpenStack and Proxmox" width="720">
  </a>
</p>

<h1 align="center">terraform-openstack-openimages</h1>

<p align="center">
  <a href="https://github.com/open-img-cloud/terraform-openstack-openimages/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/open-img-cloud/terraform-openstack-openimages/actions/workflows/ci.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="License Apache-2.0" src="https://img.shields.io/badge/license-Apache--2.0-555"></a>
</p>

<p align="center">
  <a href="https://openimages.cloud"><b>Website</b></a> ·
  <a href="https://openimages.cloud/images/">Catalog</a> ·
  <a href="https://images.openimages.cloud/index.json">index.json</a> ·
  <a href="https://github.com/open-img-cloud/oic-sync">oic-sync</a> ·
  <a href="https://github.com/open-img-cloud/terraform-openstack-openimages/issues">Report an issue</a>
</p>

Terraform and OpenTofu module that imports the signed, boot-tested cloud images of
[openimages.cloud](https://openimages.cloud) into OpenStack Glance, with the right Glance
properties.

It reads the catalog index (`https://images.openimages.cloud/index.json`, schema
`oic-index/v1`) and creates one `openstack_images_image_v2` per selected image, with the
properties of the index (`os_distro`, `hw_disk_bus`, `hw_firmware_type`...) and the same `oic_*`
keys as [oic-sync](https://github.com/open-img-cloud/oic-sync), so that other tools and data
sources recognise them.

Status: alpha. Validated with `terraform validate`, `tflint` and `terraform test` (mocked
providers); not yet applied against a real cloud.

## Which tool?

| You want | Use |
|---|---|
| Images that follow the catalog every day, old versions retired and cleaned up, signatures verified | [oic-sync](https://github.com/open-img-cloud/oic-sync) (timer, CronJob or CI job) |
| A declarative stack (a lab, a test project, a tenant bootstrap) that creates its own images next to its networks and servers | this module |
| Servers that use the images, whoever imported them | a data source lookup by `oic_id`, see [Use the images](#use-the-images) |

What Terraform cannot do, and oic-sync does:

- **Signature verification.** The module does not verify the cosign signature of the images
  (Terraform has no Sigstore support). It checks the size and the digest Glance computed
  against the index, see [Integrity](#integrity). oic-sync verifies the cosign bundle of each
  artifact against the signer identity published in the index.
- **Stable name that moves.** oic-sync gives the newest version the stable name ("Debian 13")
  and renames and hides the previous ones, which stay usable by ID. Here, a new version in the
  index replaces the Glance image: the new one is created, then the old one is **deleted**.
- **Rotation with usage checks.** oic-sync keeps `--keep` versions and deletes older ones only
  when no server and no volume uses them. Terraform deletes the replaced image at once, used or
  not (running servers keep working, but rebuilding them from that image no longer works).
- **Fallback.** oic-sync falls back from `web-download` to a streaming upload when the import
  fails at the store; the module does what `web_download` says.
- **No disk.** oic-sync streams from the CDN to Glance. Without `web_download`, the OpenStack
  provider downloads each image to `image_cache_path` first (up to about 1.3 GB per image).

Do not point both tools at the same project: oic-sync manages every image of the project that
carries an `oic_id` property, including those created by this module, and would rename, hide or
delete them behind Terraform's back.

## Usage

```hcl
provider "openstack" {}

module "images" {
  source  = "open-img-cloud/openimages/openstack"
  version = "~> 0.1"

  images   = ["debian-13", "ubuntu-24.04", "alpine-linux"]
  variants = { "alpine-linux" = ["uefi"] }
}

output "debian_image_id" {
  value = module.images.image_ids["debian-13"]
}
```

Image ids are those of the [catalog](https://openimages.cloud/images/) (or `oic-sync list`).
Each artifact gets a key, used by every output: the image id, plus `/<variant>` for the
multi-variant images (`alpine-linux/uefi`, `alpaquita-linux/musl`). See
[`examples/basic`](examples/basic) for a complete root module.

Operator, public images, Glance downloading them itself:

```hcl
module "images" {
  source  = "open-img-cloud/openimages/openstack"
  version = "~> 0.1"

  images       = ["debian-13", "debian-12", "ubuntu-24.04", "rocky-linux-10"]
  visibility   = "public"
  web_download = true
  properties   = { hw_watchdog_action = "reset" }
}
```

## How it works

1. **Read the index** with the `http` data source (or `index_json` when given), check its
   schema (`oic-index/v1`) and the requested image ids.
2. **Select** the artifacts: one per image, or one per variant for multi-variant images
   (`variants` narrows them), for `architecture` (`x86_64`).
3. **Create** one `openstack_images_image_v2` per artifact:
   - name: the catalog title, "Debian 13", or "Alpine Linux (UEFI)" for a variant (the stable
     name oic-sync uses), with `name_prefix`, or replaced by `names`;
   - `disk_format = "qcow2"`, `container_format = "bare"`, `min_disk_gb` from the virtual size;
   - properties, in this order of precedence (last wins): the optional catalog properties when
     `with_optional_properties` (`hw_rng_model=virtio`), the `glance_properties` of the
     artifact in the index, `properties`, then `oic_id`, `oic_version`, `oic_sha256` and
     `oic_variant` (variants only), which cannot be overridden;
   - data: `image_source_url` is the versioned URL of the artifact. Without `web_download`,
     the provider downloads it, uploads it and compares the MD5 Glance computed with the one of
     the local file (`verify_checksum`). With `web_download = true`, Glance downloads it itself
     (the `web-download` import method must be enabled on the cloud).
4. **Check** (lifecycle postconditions, once the image is active): the size Glance stored must
   equal the index size, and the multihash Glance computed (`os_hash_algo`/`os_hash_value`,
   sha512 by default) must equal the digest of the index for that algorithm.

When the index publishes a new version, its URL changes and the next `apply` replaces the image
(`create_before_destroy`: the new one is created before the old one is deleted). Run `plan`
first if servers reference the image ID.

`web_download` lets Glance fetch the image itself. Glance fetches with the default Python
User-Agent (`Python-urllib`), which images.openimages.cloud currently refuses (HTTP 403): until
that changes, keep the default (`web_download = false`).

### Integrity

- The MD5 check of the provider only proves that Glance received the file the provider
  downloaded, not that this file is the published one.
- The postcondition compares Glance's multihash with the index. Glance hashes with sha512 by
  default: that value comes from the build MANIFEST, fetched over HTTPS with the rest of the
  index, but it is not itself covered by the cosign signature (which covers the sha256). On a
  cloud with `hashing_algorithm = sha256` in Glance, the signed digest is the one compared.
- If a check fails, the apply fails but the image already exists and stays in the state: delete
  it (`terraform destroy -target` or `terraform apply -replace`) before using it.
- For signature verification on every import, use oic-sync, or verify the digest yourself
  first: `cosign verify-blob` as shown on each [image page](https://openimages.cloud/images/).

### Freezing versions

The index lists the latest version of each image only. To freeze the versions, commit a copy
of the index next to your configuration and pass it:

```hcl
module "images" {
  source     = "open-img-cloud/openimages/openstack"
  version    = "~> 0.1"
  images     = ["debian-13"]
  index_json = file("${path.module}/index.json")
}
```

The versioned image URLs it contains must still be served by images.openimages.cloud (or your
mirror).

## Use the images

Look images up by property, not by name, and do not let a new image version replace
long-lived servers:

```hcl
data "openstack_images_image_v2" "debian" {
  properties  = { oic_id = "debian-13" }
  most_recent = true
}

resource "openstack_compute_instance_v2" "web" {
  name        = "web1"
  image_id    = data.openstack_images_image_v2.debian.id
  flavor_name = "m1.small"

  network {
    name = "private"
  }

  lifecycle {
    ignore_changes = [image_id]
  }
}
```

This works for images imported by this module, by oic-sync, or published by your cloud
operator with oic-sync (add `visibility = "public"` to the data source to only consider those).
For a multi-variant image, add `oic_variant = "uefi"` to `properties`.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.3 (OpenTofu >= 1.6) |
| [terraform-provider-openstack/openstack](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest) | ~> 3.0 |
| [hashicorp/http](https://registry.terraform.io/providers/hashicorp/http/latest) | ~> 3.4 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `images` | Image ids of the catalog to import, e.g. `["debian-13", "ubuntu-24.04"]`. | `list(string)` | n/a | yes |
| `variants` | Variants to keep for multi-variant images, by image id, e.g. `{ "alpine-linux" = ["uefi"] }`. Images not listed get every variant. | `map(list(string))` | `{}` | no |
| `architecture` | Artifact architecture to import. | `string` | `"x86_64"` | no |
| `index_url` | URL of the catalog index (schema `oic-index/v1`). Change it to use a mirror. | `string` | `"https://images.openimages.cloud/index.json"` | no |
| `index_json` | Content of a catalog index to use instead of fetching `index_url`, e.g. `file("index.json")`. | `string` | `null` | no |
| `name_prefix` | Prefix added to every Glance image name. | `string` | `""` | no |
| `names` | Glance image names by artifact key, replacing the default name and the prefix. | `map(string)` | `{}` | no |
| `visibility` | `private`, `shared`, `community` or `public`. | `string` | `"private"` | no |
| `properties` | Extra or overriding Glance properties for every image (`oic_*` keys reserved). | `map(string)` | `{}` | no |
| `with_optional_properties` | Add `hw_rng_model=virtio` (flavors must allow `hw_rng:allowed=True`). | `bool` | `false` | no |
| `tags` | Glance tags for every image. | `list(string)` | `[]` | no |
| `web_download` | Let Glance download the images itself (`web-download` import method). | `bool` | `false` | no |
| `image_cache_path` | Download directory when `web_download` is false (`null`: provider default, `$HOME/.terraform/image_cache`). | `string` | `null` | no |
| `hidden` | Create the images with `os_hidden=true`. | `bool` | `false` | no |
| `protected` | Protect the images against deletion (this blocks their replacement by a new version). | `bool` | `false` | no |
| `require_glance_hash` | Fail when Glance reports no sha256 or sha512 multihash to compare with the index. | `bool` | `true` | no |
| `region` | OpenStack region (`null`: the provider region). | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| `image_ids` | Glance image UUIDs by artifact key (`debian-13`, `alpine-linux/uefi`). |
| `names` | Glance image names by artifact key. |
| `versions` | Imported catalog version by artifact key (`oic_version`). |
| `sha256` | sha256 of the qcow2 by artifact key (`oic_sha256`, covered by the cosign signature). |
| `images` | `id`, `name`, `oic_id`, `variant`, `version`, `sha256`, `sha512` and `url` by artifact key. |
| `index_generated_at` | `generated_at` of the index that was read. |

Checked against the documentation and source of terraform-provider-openstack v3.4.0
(`openstack_images_image_v2`: `web_download` conflicts with `verify_checksum`; properties
starting with `os_` cannot be changed after creation) and hashicorp/http v3.6.3.

## Development

```sh
terraform fmt -check -recursive
terraform init -backend=false && terraform validate
tflint --init && tflint --recursive
terraform test    # Terraform 1.9+, mocked providers; tests/live_index.tftest.hcl reads the live index
```

`tests/fixtures/index.json` is a frozen extract of the index (Debian 13 and Alpine Linux).
The tests use Terraform-only syntax: with OpenTofu, run `tofu init -test-directory=no-tests`
and `tofu validate -test-directory=no-tests`.

## License

Apache-2.0
