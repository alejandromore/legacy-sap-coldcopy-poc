# Mismo bucket de estados que nextcloud-huawei, con su propia key. Las
# credenciales temporales llegan como AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
# y AWS_SESSION_TOKEN.
terraform {
  backend "s3" {
    region = "us-east-1"
    bucket = "obs-terraform-tfstate"
    key    = "legacy-sap-coldcopy.tfstate"

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
