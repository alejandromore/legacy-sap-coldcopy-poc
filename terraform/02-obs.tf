# Bucket de transferencia: privado y cifrado del lado servidor (SSE-OBS, sin
# KMS para no sumar permisos). Sin versionado, así force_destroy lo vacía en
# el destroy (laboratorio).
#
# Prefijos:
#   incoming/<variante>/   VMDK + manifiesto, los sube "GesNet" (notebook)
#   resultados/<variante>/ hashes y tiempos que escribe el receptor
resource "huaweicloud_obs_bucket" "vmdk" {
  bucket                = var.obs_bucket_name
  acl                   = "private"
  storage_class         = "STANDARD"
  encryption            = true
  sse_algorithm         = "AES256"
  versioning            = false
  force_destroy         = true
  enterprise_project_id = var.enterprise_project_id
  tags                  = local.tags

  # Política del bucket (formato OBS): la agencia del receptor lee incoming/
  # y escribe resultados/. No da acceso a ningún otro bucket.
  policy_format = "obs"
  policy = jsonencode({
    Statement = [
      {
        Sid       = "receptor-lee-y-lista"
        Effect    = "Allow"
        Principal = { ID = ["domain/${var.domain_id}:agency/${local.agency_name}"] }
        Action    = ["ListBucket", "HeadBucket", "GetBucketLocation"]
        Resource  = [var.obs_bucket_name]
      },
      {
        Sid       = "receptor-lee-incoming"
        Effect    = "Allow"
        Principal = { ID = ["domain/${var.domain_id}:agency/${local.agency_name}"] }
        Action    = ["GetObject"]
        Resource  = ["${var.obs_bucket_name}/incoming/*"]
      },
      {
        Sid       = "receptor-escribe-resultados"
        Effect    = "Allow"
        Principal = { ID = ["domain/${var.domain_id}:agency/${local.agency_name}"] }
        Action    = ["PutObject", "AbortMultipartUpload", "ListMultipartUploadParts"]
        Resource  = ["${var.obs_bucket_name}/resultados/*"]
      },
    ]
  })

  lifecycle_rule {
    name    = "abortar-multipart"
    enabled = true

    abort_incomplete_multipart_upload {
      days = 2
    }
  }
}
