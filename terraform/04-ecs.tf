# Sin EIP en ningún ECS. Acceso por consola VNC (contraseña en el estado,
# output sensible) y, al ECS final, desde el receptor dentro de la VPC.
resource "random_password" "consola" {
  length           = 20
  special          = true
  override_special = "!@#%^*-_=+"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "huaweicloud_compute_instance" "receptor" {
  count = local.receptor_enabled ? 1 : 0

  name                        = local.receptor_name
  image_id                    = data.huaweicloud_images_image.rocky.id
  flavor_id                   = data.huaweicloud_compute_flavors.receptor.ids[0]
  availability_zone           = local.az
  security_group_ids          = [huaweicloud_networking_secgroup.lab.id]
  admin_pass                  = random_password.consola.result
  agency_name                 = huaweicloud_identity_agency.receptor.name
  system_disk_type            = var.evs_type
  system_disk_size            = 40
  delete_disks_on_termination = true
  enterprise_project_id       = var.enterprise_project_id
  user_data = templatefile("${path.module}/templates/receptor-cloud-init.yaml.tftpl", {
    bucket = var.obs_bucket_name
    region = var.region
    agente = file("${path.module}/../scripts/receptor/coldcopy-receptor.py")
  })
  tags = merge(local.tags, { rol = "receptor" })

  network {
    uuid = huaweicloud_vpc_subnet.lab.id
  }
}

# ECS SAP final: se crea apagado con un disco de sistema provisorio, que en
# la Fase 6 se reemplaza por el EVS del disco de sistema de origen. Conserva
# la IP privada del origen.
resource "huaweicloud_compute_instance" "final" {
  name                        = local.final_name
  image_id                    = data.huaweicloud_images_image.rocky.id
  flavor_id                   = data.huaweicloud_compute_flavors.final.ids[0]
  availability_zone           = local.az
  security_group_ids          = [huaweicloud_networking_secgroup.lab.id]
  admin_pass                  = random_password.consola.result
  system_disk_type            = var.evs_type
  system_disk_size            = 40
  delete_disks_on_termination = false
  power_action                = "OFF"
  enterprise_project_id       = var.enterprise_project_id
  tags                        = merge(local.tags, { rol = "sap-final" })

  network {
    uuid        = huaweicloud_vpc_subnet.lab.id
    fixed_ip_v4 = var.ip_origen
  }

  # El disco de sistema y el encendido los cambia la Fase 6 fuera de Terraform.
  lifecycle {
    ignore_changes = [power_action, system_disk_type, system_disk_size, image_id]
  }
}
