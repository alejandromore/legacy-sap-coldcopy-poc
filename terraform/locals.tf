locals {
  prefix = var.app_env

  vpc_name      = "vpc-${local.prefix}"
  subnet_name   = "subnet-${local.prefix}"
  sg_name       = "sg-${local.prefix}"
  receptor_name = "ecs-${local.prefix}-receptor"
  final_name    = "ecs-${local.prefix}-sap-final"
  agency_name   = "agency-${local.prefix}-receptor"

  # El receptor vive en las dos etapas: en "recepcion" con los EVS conectados;
  # en "final" sin ellos, como punto de verificación del ECS final dentro de
  # la VPC (simula el acceso de Integratel). Se elimina con el destroy.
  receptor_enabled = true
  evs_en_receptor  = var.etapa == "recepcion"

  tags = merge(var.tags, { app_env = var.app_env })
}
