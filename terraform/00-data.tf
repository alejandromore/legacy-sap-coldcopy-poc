data "huaweicloud_availability_zones" "azs" {}

locals {
  az = data.huaweicloud_availability_zones.azs.names[0]
}

data "huaweicloud_compute_flavors" "receptor" {
  availability_zone = local.az
  performance_type  = "normal"
  cpu_core_count    = var.receptor_cpu
  memory_size       = var.receptor_memory
  generation        = var.flavor_generation
}

data "huaweicloud_compute_flavors" "final" {
  availability_zone = local.az
  performance_type  = "normal"
  cpu_core_count    = var.final_cpu
  memory_size       = var.final_memory
  generation        = var.flavor_generation
}

data "huaweicloud_images_image" "rocky" {
  name_regex  = var.image_name_regex
  visibility  = "public"
  most_recent = true
}
