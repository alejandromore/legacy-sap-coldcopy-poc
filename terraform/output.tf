output "obs_bucket" {
  value = huaweicloud_obs_bucket.vmdk.bucket
}

output "receptor_private_ip" {
  value = try(huaweicloud_compute_instance.receptor[0].access_ip_v4, null)
}

output "final_id" {
  value = huaweicloud_compute_instance.final.id
}

output "final_private_ip" {
  value = huaweicloud_compute_instance.final.access_ip_v4
}

output "evs" {
  value = { for k, v in huaweicloud_evs_volume.disco : k => { id = v.id, size = v.size } }
}

output "consola_password" {
  value     = random_password.consola.result
  sensitive = true
}

output "etapa" {
  value = var.etapa
}
