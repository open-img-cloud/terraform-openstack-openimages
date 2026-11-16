variable "images" {
  description = "Image ids of the openimages.cloud catalog to import, e.g. [\"debian-13\", \"ubuntu-24.04\"]. See https://openimages.cloud/images/ or `oic-sync list`."
  type        = list(string)

  validation {
    condition     = length(var.images) > 0
    error_message = "List at least one image id."
  }
}

variable "variants" {
  description = "Variants to keep for multi-variant images, by image id, e.g. { \"alpine-linux\" = [\"uefi\"] }. Images not listed here get every variant."
  type        = map(list(string))
  default     = {}
}

variable "architecture" {
  description = "Artifact architecture to import."
  type        = string
  default     = "x86_64"
}

variable "index_url" {
  description = "URL of the catalog index (schema oic-index/v1). Change it to use a mirror."
  type        = string
  default     = "https://images.openimages.cloud/index.json"
}

variable "index_json" {
  description = "Content of a catalog index to use instead of fetching index_url, e.g. file(\"index.json\") to freeze the versions in your repository. The image URLs it lists must still be reachable."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Prefix added to every Glance image name, e.g. \"oic/\" gives \"oic/Debian 13\"."
  type        = string
  default     = ""
}

variable "names" {
  description = "Glance image names by artifact key (\"debian-13\", \"alpine-linux/uefi\"), replacing the default name (the catalog title) and the prefix."
  type        = map(string)
  default     = {}
}

variable "visibility" {
  description = "Glance visibility: private, shared, community or public (public usually needs an admin role)."
  type        = string
  default     = "private"

  validation {
    condition     = contains(["private", "shared", "community", "public"], var.visibility)
    error_message = "visibility must be private, shared, community or public."
  }
}

variable "properties" {
  description = "Extra or overriding Glance properties for every image. The oic_* keys are reserved."
  type        = map(string)
  default     = {}

  validation {
    condition     = length([for k in keys(var.properties) : k if length(regexall("^oic_", k)) > 0]) == 0
    error_message = "The oic_* properties are set by the module and cannot be overridden."
  }
}

variable "with_optional_properties" {
  description = "Add the optional Glance properties of the catalog (hw_rng_model=virtio): flavors must then allow hw_rng:allowed=True."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Glance tags for every image."
  type        = list(string)
  default     = []
}

variable "web_download" {
  description = "Let Glance download the images itself (web-download import method, must be enabled on the cloud). When false, the provider downloads each image to image_cache_path, then uploads it. Note: images.openimages.cloud currently answers 403 to the Python-urllib User-Agent Glance uses."
  type        = bool
  default     = false
}

variable "image_cache_path" {
  description = "Directory for downloaded images when web_download is false. Null keeps the provider default ($HOME/.terraform/image_cache)."
  type        = string
  default     = null
}

variable "hidden" {
  description = "Create the images with os_hidden=true: usable by id, left out of image lists."
  type        = bool
  default     = false
}

variable "protected" {
  description = "Protect the images against deletion. A protected image blocks its own replacement when a new version is published."
  type        = bool
  default     = false
}

variable "require_glance_hash" {
  description = "Fail when Glance reports no sha256 or sha512 multihash (os_hash_algo) to compare with the index. Glance computes sha512 by default since the Rocky release."
  type        = bool
  default     = true
}

variable "region" {
  description = "OpenStack region. Null uses the provider region."
  type        = string
  default     = null
}
