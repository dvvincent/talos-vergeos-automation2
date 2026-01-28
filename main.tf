resource "vergeio_vm" "talos_cp" {
  name         = "talos-cp-02"
  cpu_cores    = 4
  ram          = 8192
  powerstate   = true
  boot_order   = "c" # Prioritize CD-ROM

  vergeio_drive {
    name      = "OS Disk"
    disksize  = 50
    interface = "virtio-scsi"
    media     = "disk"
  }

  vergeio_drive {
    name         = "Talos ISO"
    media        = "cdrom"
    media_source = var.talos_image_id # Dynamic ID discovered in Phase 0
    interface    = "ide"              # Maximum compatibility
  }

  vergeio_nic {
    name = "eth0"
    vnet = "17" # Targeted Kubernetes Network
  }
}

resource "vergeio_vm" "talos_worker" {
  name         = "talos-worker-02"
  cpu_cores    = 4
  ram          = 8192
  powerstate   = true
  boot_order   = "c" # Prioritize CD-ROM

  vergeio_drive {
    name      = "OS Disk"
    disksize  = 50
    interface = "virtio-scsi"
    media     = "disk"
  }

  vergeio_drive {
    name         = "Talos ISO"
    media        = "cdrom"
    media_source = var.talos_image_id # Dynamic ID discovered in Phase 0
    interface    = "ide"              # Maximum compatibility
  }

  vergeio_nic {
    name = "eth0"
    vnet = "17" # Targeted Kubernetes Network
  }
}

output "talos_cp_ip" {
  value = vergeio_vm.talos_cp.vergeio_nic[0].ipaddress
}

output "talos_worker_ip" {
  value = vergeio_vm.talos_worker.vergeio_nic[0].ipaddress
}
