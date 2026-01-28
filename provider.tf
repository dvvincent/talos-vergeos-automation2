terraform {
  required_providers {
    vergeio = {
      source = "verge-io/vergeio"
    }
  }
}

provider "vergeio" {
  host     = var.vergeos_host
  username = var.vergeos_user
  password = var.vergeos_pass
  insecure = true
}
