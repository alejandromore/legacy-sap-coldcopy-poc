terraform {
  required_version = ">= 1.9.0"

  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = ">= 1.87.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }
}

# Credenciales: HW_ACCESS_KEY, HW_SECRET_KEY y HW_SECURITY_TOKEN temporales,
# obtenidas por OIDC en el workflow (.github/actions/huawei-oidc).
provider "huaweicloud" {
  region                = var.region
  enterprise_project_id = var.enterprise_project_id
}
