resource "huaweicloud_vpc" "lab" {
  name                  = local.vpc_name
  cidr                  = var.vpc_cidr
  enterprise_project_id = var.enterprise_project_id
  tags                  = local.tags
}

resource "huaweicloud_vpc_subnet" "lab" {
  name       = local.subnet_name
  vpc_id     = huaweicloud_vpc.lab.id
  cidr       = var.subnet_cidr
  gateway_ip = var.subnet_gateway
  dns_list   = var.dns_list
  tags       = local.tags
}

# Sin ninguna entrada desde Internet: ningún ECS tiene IP pública. Solo se
# permite el tráfico entre miembros del grupo (receptor <-> ECS final).
resource "huaweicloud_networking_secgroup" "lab" {
  name                  = local.sg_name
  description           = "Laboratorio coldcopy: sin acceso desde Internet"
  enterprise_project_id = var.enterprise_project_id
  delete_default_rules  = true
}

resource "huaweicloud_networking_secgroup_rule" "intra_ingress" {
  security_group_id = huaweicloud_networking_secgroup.lab.id
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_group_id   = huaweicloud_networking_secgroup.lab.id
}

resource "huaweicloud_networking_secgroup_rule" "egress" {
  security_group_id = huaweicloud_networking_secgroup.lab.id
  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
}
