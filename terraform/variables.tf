variable "region" {
  type        = string
  default     = "la-south-2"
  description = "Región de Huawei Cloud (Santiago)"
}

variable "enterprise_project_id" {
  type        = string
  default     = "0"
  description = "Enterprise Project. 0 = default"
}

variable "app_env" {
  type        = string
  default     = "legacy-coldcopy"
  description = "Prefijo de los recursos"
}

variable "etapa" {
  type        = string
  default     = "recepcion"
  description = "recepcion: EVS conectados al receptor. final: receptor eliminado y EVS libres para el ECS SAP final"

  validation {
    condition     = contains(["recepcion", "final"], var.etapa)
    error_message = "etapa debe ser recepcion o final."
  }
}

# Red: mismo rango que la red NAT de VMware, para que el ECS final conserve
# la IP privada del origen.
variable "vpc_cidr" {
  type    = string
  default = "192.168.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "192.168.63.0/24"
}

variable "subnet_gateway" {
  type        = string
  default     = "192.168.63.2"
  description = "Mismo gateway que VMware NAT (.2) para no tocar ifcfg-eth0. Si Huawei lo rechaza, usar .1 y ajustarlo en la preparación VirtIO"
}

variable "dns_list" {
  type    = list(string)
  default = ["100.125.1.250", "100.125.21.250"]
}

variable "ip_origen" {
  type        = string
  default     = "192.168.63.50"
  description = "IP fija de rhel51-origen, que conserva el ECS SAP final"
}

variable "obs_bucket_name" {
  type        = string
  default     = "obs-legacy-coldcopy-vmdk"
  description = "Bucket de transferencia (nombre global en OBS)"
}

# Un EVS por VMDK, en el mismo orden que los discos de origen. Tamaño mayor o
# igual al disco virtual (el de sistema respeta el mínimo de un ECS).
variable "discos" {
  type = list(object({
    nombre = string
    size   = number
  }))
  default = [
    { nombre = "sistema", size = 40 },
    { nombre = "datos", size = 10 },
  ]
}

variable "evs_type" {
  type    = string
  default = "GPSSD"
}

variable "receptor_cpu" {
  type    = number
  default = 2
}

variable "receptor_memory" {
  type    = number
  default = 4
}

variable "final_cpu" {
  type    = number
  default = 2
}

variable "final_memory" {
  type    = number
  default = 4
}

variable "flavor_generation" {
  type        = string
  default     = null
  description = "Generación de flavor (ej. s6). Para el kernel 2.6.18 puede convenir una generación antigua"
}

variable "image_name_regex" {
  type    = string
  default = "^Rocky Linux 9"
}

variable "tags" {
  type = map(string)
  default = {
    proyecto = "legacy-sap-coldcopy-poc"
    temporal = "true"
  }
}
