locals {
  prefix = var.app_env

  vpc_name      = "vpc-${local.prefix}"
  subnet_name   = "subnet-${local.prefix}"
  sg_name       = "sg-${local.prefix}"
  receptor_name = "ecs-${local.prefix}-receptor"
  final_name    = "ecs-${local.prefix}-sap-final"
  agency_name   = "agency-${local.prefix}-receptor"

  receptor_enabled = var.etapa == "recepcion"

  tags = merge(var.tags, { app_env = var.app_env })
}
