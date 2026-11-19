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

locals {
  receptor_user_data = templatefile("${path.module}/templates/receptor-cloud-init.yaml.tftpl", {
    bucket = var.obs_bucket_name
    region = var.region
    agente = file("${path.module}/../scripts/receptor/coldcopy-receptor.py")
  })
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
  user_data                   = local.receptor_user_data
  tags                        = merge(local.tags, { rol = "receptor" })

  network {
    uuid = huaweicloud_vpc_subnet.lab.id
  }

  # cloud-init solo corre al crear el ECS: un user_data nuevo exige otro ECS.
  lifecycle {
    replace_triggered_by = [terraform_data.receptor_user_data]
  }
}

resource "terraform_data" "receptor_user_data" {
  input = sha256(local.receptor_user_data)
}

# ECS SAP final: se crea apagado con un disco de sistema provisorio, que en
# la Fase 6 se reemplaza por el EVS del disco de sistema de origen. Conserva
# la IP privada del origen.
resource "huaweicloud_compute_instance" "final" {
  name                  = local.final_name
  image_id              = data.huaweicloud_images_image.rocky.id
  flavor_id             = data.huaweicloud_compute_flavors.final.ids[0]
  availability_zone     = local.az
  security_group_ids    = [huaweicloud_networking_secgroup.lab.id]
  admin_pass            = random_password.consola.result
  system_disk_type      = var.evs_type
  system_disk_size      = 40
  power_action          = "OFF"
  enterprise_project_id = var.enterprise_project_id
  tags                  = merge(local.tags, { rol = "sap-final" })

  # Destroy seguro: al borrar el ECS final se borran los discos que tenga
  # conectados en ese momento, incluido uno que Terraform no conozca (el disco
  # de sistema provisorio si armar-final no llegó a borrarlo). Los EVS del
  # estado que ya no existan se dan por borrados.
  delete_disks_on_termination = true

  network {
    uuid        = huaweicloud_vpc_subnet.lab.id
    fixed_ip_v4 = var.ip_origen
  }

  # El ECS final se destruye ANTES que los EVS: así no se intenta borrar un
  # EVS mientras sigue conectado a él.
  depends_on = [huaweicloud_evs_volume.disco]

  # El disco de sistema y el encendido los cambia la Fase 6 fuera de Terraform.
  lifecycle {
    ignore_changes = [power_action, system_disk_type, system_disk_size, image_id]
  }
}
