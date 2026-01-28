variable "vergeos_host" {
  type        = string
  description = "VergeOS Host URL/IP"
  default     = "192.168.1.111" 
}

variable "vergeos_user" {
  type        = string
  description = "VergeOS Username"
}

variable "vergeos_pass" {
  type        = string
  description = "VergeOS Password"
  sensitive   = true
}

variable "talos_image_id" {
  type        = string
  description = "ID of the Talos ISO image in VergeOS"
  default     = "107"
}
