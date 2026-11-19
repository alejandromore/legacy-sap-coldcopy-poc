# ============================================================================
# Bootstrap: federación OIDC GitHub Actions -> Huawei Cloud IAM
#
# Se aplica UNA sola vez, en local, con las AK/SK de administrador en
# variables de entorno (HW_ACCESS_KEY/HW_SECRET_KEY y AWS_* para el backend).
# Con Terraform >= 1.11 exportar además AWS_REQUEST_CHECKSUM_CALCULATION y
# AWS_RESPONSE_CHECKSUM_VALIDATION en when_required: OBS rechaza (400) los
# checksums que el backend s3 agrega por defecto al guardar el estado.
# Después de esto GitHub Actions obtiene credenciales temporales con su token
# OIDC y ya no hace falta ninguna AK/SK guardada en GitHub.
#
# Crea:
#   1) Proveedor de identidad OIDC (acceso programático) que confía en
#      token.actions.githubusercontent.com con la audiencia var.audience.
#   2) Regla de conversión: solo los jobs del repo y environment indicados
#      (claim "sub") se convierten en el usuario federado, miembro del grupo.
#   3) Grupo IAM con los permisos que necesita Terraform para el laboratorio.
# ============================================================================

terraform {
  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = ">= 1.87.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.4.0"
    }
  }

  backend "s3" {
    region = "us-east-1"
    bucket = "obs-terraform-tfstate"
    key    = "legacy-sap-coldcopy-bootstrap.tfstate"

    endpoints = {
      s3 = "https://obs.la-south-2.myhuaweicloud.com"
    }

    use_path_style              = false
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}

provider "huaweicloud" {
  region                = var.region
  enterprise_project_id = "0" # EP default
}

variable "region" {
  type    = string
  default = "la-south-2"
}

variable "domain_id" {
  type        = string
  description = "ID de la cuenta (Mi credencial > ID de cuenta). Exportar TF_VAR_domain_id"
}

variable "github_repo" {
  type        = string
  default     = "alejandromore/legacy-sap-coldcopy-poc"
  description = "owner/repo autorizado a federarse"
}

variable "github_environment" {
  type        = string
  default     = "huawei-lab"
  description = "Environment de GitHub autorizado (el claim sub lo incluye)"
}

variable "audience" {
  type        = string
  default     = "huaweicloud"
  description = "Audiencia (aud) que pide el workflow; debe coincidir con client_id"
}

locals {
  prefix   = "legacy-coldcopy"
  idp_name = "github-${local.prefix}"
  subject  = "repo:${var.github_repo}:environment:${var.github_environment}"
}

# Claves públicas con las que GitHub firma sus tokens OIDC. Si GitHub las
# rota, volver a aplicar este bootstrap.
data "http" "github_jwks" {
  url = "https://token.actions.githubusercontent.com/.well-known/jwks"
}

resource "huaweicloud_identity_provider" "github" {
  name        = local.idp_name
  protocol    = "oidc"
  description = "GitHub Actions de ${var.github_repo}"
  status      = true

  access_config {
    access_type  = "program"
    provider_url = "https://token.actions.githubusercontent.com"
    client_id    = var.audience
    signing_key  = data.http.github_jwks.response_body
  }

  # Solo aplican al inicio de sesión en consola; IAM no los devuelve para
  # acceso programático y Terraform los vería como cambio en cada plan.
  lifecycle {
    ignore_changes = [access_config[0].response_mode, access_config[0].response_type]
  }
}

resource "huaweicloud_identity_group" "github" {
  name        = "grp-${local.prefix}-github"
  description = "Usuario federado de GitHub Actions para el laboratorio legacy-sap-coldcopy"
}

resource "huaweicloud_identity_provider_conversion" "github" {
  provider_id = huaweicloud_identity_provider.github.id

  conversion_rules {
    local {
      username = "github-${local.prefix}"
    }
    local {
      group = huaweicloud_identity_group.github.name
    }
    remote {
      attribute = "sub"
      condition = "any_one_of"
      value     = [local.subject]
    }
  }
}

# Permisos del grupo. Laboratorio: Tenant Administrator (todos los servicios
# salvo IAM) en todos los proyectos + Security Administrator (IAM), porque
# Terraform crea la agencia y el rol del receptor. Para producción, reducir a
# políticas por servicio.
data "huaweicloud_identity_role" "tenant_admin" {
  name = "te_admin"
}

data "huaweicloud_identity_role" "security_admin" {
  name = "secu_admin"
}

resource "huaweicloud_identity_group_role_assignment" "tenant_admin" {
  group_id   = huaweicloud_identity_group.github.id
  role_id    = data.huaweicloud_identity_role.tenant_admin.id
  project_id = "all"
}

resource "huaweicloud_identity_group_role_assignment" "security_admin" {
  group_id  = huaweicloud_identity_group.github.id
  role_id   = data.huaweicloud_identity_role.security_admin.id
  domain_id = var.domain_id
}

output "idp_id" {
  value       = huaweicloud_identity_provider.github.id
  description = "Variable HW_IDP_ID del environment de GitHub"
}

output "subject" {
  value = local.subject
}
