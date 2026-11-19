# Un EVS por VMDK de origen. Sobreviven al cambio de etapa: en "recepcion"
# están conectados al receptor; en "final" quedan libres para el ECS SAP
# final.
#
# El primero (orden 0) es el disco de sistema y se crea DESDE UNA IMAGEN:
# Huawei solo acepta como disco de sistema un EVS creado desde imagen (un EVS
# vacío da "device is illegal" aunque se marque bootable). Por eso el
# manifiesto lo marca "limpiar": el receptor pone en cero el tramo del disco
# de origen antes de escribir, y el SHA-256 se compara igual.
resource "huaweicloud_evs_volume" "disco" {
  for_each = { for i, d in var.discos : d.nombre => merge(d, { orden = i }) }

  name                  = "evs-${local.prefix}-${each.key}"
  description           = "Copia del VMDK ${each.key} (orden ${each.value.orden})"
  volume_type           = var.evs_type
  size                  = each.value.size
  image_id              = each.value.orden == 0 ? data.huaweicloud_images_image.rocky.id : null
  availability_zone     = local.az
  enterprise_project_id = var.enterprise_project_id
  tags                  = merge(local.tags, { disco = each.key, orden = tostring(each.value.orden) })
}

resource "huaweicloud_compute_volume_attach" "receptor" {
  for_each = local.evs_en_receptor ? huaweicloud_evs_volume.disco : {}

  instance_id = huaweicloud_compute_instance.receptor[0].id
  volume_id   = each.value.id
}
