# Agencia del receptor: lee los VMDK y escribe resultados con las credenciales
# temporales del metadata service. Ninguna AK/SK vive en el ECS.
resource "huaweicloud_identity_role" "receptor_obs" {
  name        = "custom-${local.prefix}-receptor-obs"
  description = "Receptor coldcopy: leer incoming/ y escribir resultados/"
  type        = "AX" # OBS es global

  policy = jsonencode({
    Version = "1.1"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "obs:bucket:HeadBucket",
          "obs:bucket:GetBucketLocation",
          "obs:bucket:ListBucket",
        ]
        Resource = ["obs:*:*:bucket:${var.obs_bucket_name}"]
      },
      {
        Effect   = "Allow"
        Action   = ["obs:object:GetObject"]
        Resource = ["obs:*:*:object:${var.obs_bucket_name}/incoming/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "obs:object:PutObject",
          "obs:object:AbortMultipartUpload",
          "obs:object:ListMultipartUploadParts",
        ]
        Resource = ["obs:*:*:object:${var.obs_bucket_name}/resultados/*"]
      },
    ]
  })
}

resource "huaweicloud_identity_agency" "receptor" {
  name                   = local.agency_name
  description            = "Receptor coldcopy: acceso a su bucket OBS"
  delegated_service_name = "op_svc_ecs"
  # Con solo el rol personalizado (en servicios globales o en todos los
  # recursos) OBS respondió AccessDenied a las credenciales temporales del
  # metadata service; con OBS OperateAccess funciona. Es más amplio que lo
  # necesario (todos los buckets de la cuenta): pendiente acotarlo con una
  # política de bucket. El rol personalizado queda para documentar la intención.
  all_resources_roles = [huaweicloud_identity_role.receptor_obs.name, "OBS OperateAccess"]
}
