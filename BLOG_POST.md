# Zero to K8s in Minutes: The Complete Guide to Talos Linux on VergeOS

**What if I told you that you could deploy a production-grade Kubernetes cluster in under 2 minutes—with zero SSH access, no package managers, and a completely immutable OS?**

Most Kubernetes deployments involve hours of configuration, security hardening, and manual intervention. You're juggling Ansible playbooks, fighting with systemd, and praying your SSH keys don't get compromised. There's a better way.

**Immutability isn't just a buzzword; it's a security posture.** And when you combine Talos Linux—a Kubernetes-only OS with no shell access—with VergeOS's API-driven infrastructure, you get something remarkable: a fully automated, security-hardened cluster that goes from zero to production in the time it takes to grab a coffee.

In our [previous article](https://blog.homelabadventures.com/ditch-the-dashboard-mastering-vergeos-with-verge-cli/), we explored how to break free from the GUI and master VergeOS using the `verge-cli`. Today, we're taking that automation to the next level by deploying **Talos Linux** on VergeOS using **Terraform**.

This isn't a theoretical guide. This is the complete, battle-tested workflow including every wait time, every troubleshooting step, and every detail you need to successfully deploy production-grade Kubernetes clusters on VergeOS. We're going from VM creation to `kubectl get nodes` in **121 seconds**.

---

## 🚀 Why Talos on VergeOS?

Talos Linux removes the complexity of traditional Linux distributions. There is no SSH, no shells, and the entire filesystem is read-only. Management is handled exclusively via a gRPC API (`talosctl`).

When paired with VergeOS's high-performance VSAN and native API, you get a "Mini-Cloud" that is:
1. **Immutable**: OS configuration is defined in a single YAML file
2. **Self-Healing**: Talos manages the K8s lifecycle automatically
3. **Atomic**: Updates are handled via image swaps, not package managers
4. **API-Driven**: Everything from VM provisioning to cluster bootstrapping is automated

---

## 📋 Prerequisites

Before starting, ensure you have:

- **VergeOS Instance**: Running and accessible (e.g., `192.168.1.111`)
- **Admin Credentials**: Username and password for API access
- **Terraform**: Installed with the VergeOS provider configured
- **talosctl**: v1.12.2 or compatible version
- **kubectl**: For Kubernetes cluster management
- **Python 3**: For the IP discovery script
- **Network**: A VergeOS vnet configured for your VMs (e.g., vnet 17)

---

## 🏗️ The Complete Deployment Architecture

Our workflow consists of these phases:

1. **VM Provisioning**: Deploy VMs with Terraform
2. **IP Discovery**: Automatically find VM IP addresses
3. **Configuration Generation**: Create Talos configs for control plane and workers
4. **Cluster Initialization**: Apply configs and bootstrap the cluster
5. **Verification**: Confirm cluster health and readiness

---

## 📦 Phase 1: VM Provisioning with Terraform

### Directory Structure

```
talos-vergeos-automation/
├── main.tf                 # VM resource definitions
├── provider.tf             # VergeOS provider configuration
├── variables.tf            # Input variables
├── scripts/
│   └── get_verge_ip.py    # IP discovery automation
└── README.md
```

### Terraform Configuration

**`provider.tf`:**
```hcl
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
```

**`variables.tf`:**
```hcl
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
  default     = "107"  # Update with your ISO ID
}
```

**`main.tf`:**
```hcl
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
    media_source = var.talos_image_id
    interface    = "ide"
  }

  vergeio_nic {
    name = "eth0"
    vnet = "17"  # Your Kubernetes network
  }
}

resource "vergeio_vm" "talos_worker" {
  name         = "talos-worker-02"
  cpu_cores    = 4
  ram          = 8192
  powerstate   = true
  boot_order   = "c"

  vergeio_drive {
    name      = "OS Disk"
    disksize  = 50
    interface = "virtio-scsi"
    media     = "disk"
  }

  vergeio_drive {
    name         = "Talos ISO"
    media        = "cdrom"
    media_source = var.talos_image_id
    interface    = "ide"
  }

  vergeio_nic {
    name = "eth0"
    vnet = "17"
  }
}

output "talos_cp_ip" {
  value = vergeio_vm.talos_cp.vergeio_nic[0].ipaddress
}

output "talos_worker_ip" {
  value = vergeio_vm.talos_worker.vergeio_nic[0].ipaddress
}
```

### Deploy the VMs

```bash
# Initialize Terraform
terraform init

# Deploy the infrastructure
terraform apply -var="vergeos_user=admin" -var="vergeos_pass=YourPassword" -auto-approve
```

**Expected Output:**
```
vergeio_vm.talos_cp: Creating...
vergeio_vm.talos_worker: Creating...
vergeio_vm.talos_cp: Creation complete after 11s [id=72]
vergeio_vm.talos_worker: Creation complete after 11s [id=73]

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

**⏱️ Timing Note:** VM creation takes approximately **10-15 seconds**.

---

## 🔍 Phase 2: Automated IP Discovery

The VMs boot from the Talos ISO and obtain DHCP addresses. We use a custom Python script to discover these IPs automatically.

### The IP Discovery Script

**`scripts/get_verge_ip.py`:**
```python
#!/usr/bin/env python3
import argparse
import json
import os
import sys
import requests
import urllib3
import time

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def get_env_var(var_name, default=None):
    return os.environ.get(var_name, default)

VERGE_HOST = get_env_var("VERGEOS_HOST", "192.168.1.111")
VERGE_USER = get_env_var("VERGEOS_USER", "admin")
VERGE_PASS = get_env_var("VERGEOS_PASS")

def api_request(method, endpoint, auth=None, params=None):
    url = f"https://{VERGE_HOST}/api{endpoint}"
    try:
        if method == "GET":
            response = requests.get(url, auth=auth, params=params, verify=False)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Get VergeOS VM IP Address")
    parser.add_argument("--machine-name", type=str, required=True, help="Machine Name")
    parser.add_argument("--timeout", type=int, default=300, help="Wait timeout in seconds")
    
    args = parser.parse_args()
    auth = (VERGE_USER, VERGE_PASS)
    
    # Resolve machine name to ID
    params = {"filter": f"name eq '{args.machine_name}'"}
    vms = api_request("GET", "/v4/vms", auth=auth, params=params)
    if not vms:
        print(f"Machine '{args.machine_name}' not found.", file=sys.stderr)
        sys.exit(1)
    
    machine_id = vms[0]['machine']
    print(f"Resolved '{args.machine_name}' to Machine ID: {machine_id}", file=sys.stderr)

    # Wait for IP address
    start_time = time.time()
    attempt = 0
    while True:
        params = {"filter": f"machine eq {machine_id}"}
        nics = api_request("GET", "/v4/machine_nics", auth=auth, params=params)
        
        for nic in nics:
            mac = nic.get('macaddress')
            if not mac:
                continue
            
            params = {"filter": f"mac eq '{mac}'"}
            addrs = api_request("GET", "/v4/vnet_addresses", auth=auth, params=params)
            
            for addr in addrs:
                ip = addr.get('ip')
                if ip:
                    print(ip)
                    sys.exit(0)
        
        if (time.time() - start_time) > args.timeout:
            print(f"Timeout waiting for IP", file=sys.stderr)
            sys.exit(1)
        
        elapsed = int(time.time() - start_time)
        print(f"Waiting for IP... ({elapsed}/{args.timeout}s)", file=sys.stderr)
        time.sleep(5)
        attempt += 1

if __name__ == "__main__":
    main()
```

### Discover VM IP Addresses

```bash
# Set credentials
export VERGEOS_USER="admin"
export VERGEOS_PASS="YourPassword"

# Discover control plane IP (waits up to 5 minutes)
CP_IP=$(python3 scripts/get_verge_ip.py --machine-name talos-cp-02 --timeout 300)
echo "Control Plane IP: $CP_IP"

# Discover worker IP
WORKER_IP=$(python3 scripts/get_verge_ip.py --machine-name talos-worker-02 --timeout 300)
echo "Worker IP: $WORKER_IP"
```

**Expected Output:**
```
Resolved 'talos-cp-02' to Machine ID: 94
Waiting for IP... (0/300s)
10.0.6.166

Resolved 'talos-worker-02' to Machine ID: 95
10.0.6.165
```

**⏱️ Timing Note:** IP discovery typically takes **5-30 seconds** after VM boot, depending on DHCP response time.

---

## ⚙️ Phase 3: Generate Talos Configuration

With the IP addresses discovered, generate the Talos cluster configuration.

```bash
# Generate configuration for the cluster
talosctl gen config talos-cluster-2 https://$CP_IP:6443
```

**Expected Output:**
```
generating PKI and tokens
Created /path/to/controlplane.yaml
Created /path/to/worker.yaml
Created /path/to/talosconfig
```

This creates three files:
- **`controlplane.yaml`**: Configuration for control plane nodes
- **`worker.yaml`**: Configuration for worker nodes
- **`talosconfig`**: Client configuration for `talosctl`

**⏱️ Timing Note:** Configuration generation is **instant** (< 1 second).

---

## 🚀 Phase 4: Apply Configuration and Bootstrap

### Step 1: Apply Configuration to Nodes

```bash
# Apply control plane configuration
talosctl apply-config --nodes $CP_IP --file controlplane.yaml --insecure

# Apply worker configuration
talosctl apply-config --nodes $WORKER_IP --file worker.yaml --insecure
```

**⏱️ Timing Note:** Each `apply-config` command completes in **1-2 seconds**, but the nodes need time to process the configuration.

**⚠️ CRITICAL WAIT TIME:** After applying configurations, **wait 30-60 seconds** before bootstrapping to allow:
- Talos to process the configuration
- etcd to initialize
- Network stack to stabilize
- API server to become available

### Step 2: Configure talosctl Client

```bash
# Set the endpoint and node for talosctl
talosctl --talosconfig talosconfig config endpoint $CP_IP
talosctl --talosconfig talosconfig config node $CP_IP
```

### Step 3: Bootstrap the Cluster

```bash
# Wait for Talos API to be ready
sleep 30

# Bootstrap the cluster
talosctl --talosconfig talosconfig bootstrap
```

**Expected Output:**
```
(no output means success)
```

**⏱️ Timing Note:** Bootstrap command completes in **1-2 seconds**, but cluster initialization continues in the background.

**⚠️ CRITICAL WAIT TIME:** After bootstrapping, **wait 30-60 seconds** for:
- Kubernetes control plane components to start
- CoreDNS to initialize
- CNI (Flannel) to configure networking
- Nodes to register with the API server

---

## 🔍 Phase 5: Retrieve kubeconfig and Verify

### Get kubeconfig

```bash
# Retrieve the kubeconfig
talosctl --talosconfig talosconfig kubeconfig .
```

This creates a `kubeconfig` file in the current directory.

### Verify Cluster Status

```bash
# Check nodes (may show NotReady initially)
kubectl --kubeconfig kubeconfig get nodes -o wide
```

**First Check (immediately after bootstrap):**
```
NAME            STATUS     ROLES           AGE   VERSION
talos-8p4-ekr   NotReady   control-plane   1s    v1.35.0
```

**⏱️ CRITICAL WAIT TIME:** **Wait 20-30 seconds** for nodes to become Ready.

**Second Check (after 30 seconds):**
```bash
kubectl --kubeconfig kubeconfig get nodes -o wide
```

```
NAME            STATUS   ROLES           AGE   VERSION   INTERNAL-IP   OS-IMAGE
talos-8p4-ekr   Ready    control-plane   32s   v1.35.0   10.0.6.166    Talos (v1.12.2)
talos-645-r38   Ready    <none>          13s   v1.35.0   10.0.6.165    Talos (v1.12.2)
```

### Verify System Pods

```bash
kubectl --kubeconfig kubeconfig get pods -A
```

**Expected Output:**
```
NAMESPACE     NAME                                    READY   STATUS    RESTARTS   AGE
kube-system   coredns-7859998f6-jzp4v                 1/1     Running   0          46s
kube-system   coredns-7859998f6-sz8x6                 1/1     Running   0          46s
kube-system   kube-apiserver-talos-8p4-ekr            1/1     Running   0          39s
kube-system   kube-controller-manager-talos-8p4-ekr   1/1     Running   2          39s
kube-system   kube-flannel-g6kzp                      1/1     Running   0          41s
kube-system   kube-flannel-mhxnk                      1/1     Running   0          22s
kube-system   kube-proxy-8xnxj                        1/1     Running   0          22s
kube-system   kube-proxy-npwjm                        1/1     Running   0          41s
kube-system   kube-scheduler-talos-8p4-ekr            1/1     Running   0          39s
```

---

## ⏱️ Complete Timing Breakdown

Here's the complete timeline from start to finish:

| Phase | Step | Time | Cumulative |
|-------|------|------|------------|
| 1 | Terraform init | 5s | 5s |
| 1 | Terraform apply (VM creation) | 11s | 16s |
| 2 | IP discovery (control plane) | 10s | 26s |
| 2 | IP discovery (worker) | 5s | 31s |
| 3 | Generate Talos config | 1s | 32s |
| 4 | Apply control plane config | 2s | 34s |
| 4 | Apply worker config | 2s | 36s |
| 4 | **WAIT** for Talos API | 30s | 66s |
| 4 | Bootstrap cluster | 2s | 68s |
| 4 | **WAIT** for K8s initialization | 30s | 98s |
| 5 | Retrieve kubeconfig | 1s | 99s |
| 5 | **WAIT** for nodes Ready | 20s | 119s |
| 5 | Verify cluster | 2s | 121s |

**Total Time: ~2 minutes from zero to fully operational cluster**

---

## 🛠️ Managing Existing Clusters

### Shutting Down VMs

When you need to shut down your cluster VMs:

```bash
# Using the VergeOS API (correct endpoint)
curl -k -u "admin:YourPassword" -X POST \
  "https://192.168.1.111/api/v4/vms/72/poweroff"

curl -k -u "admin:YourPassword" -X POST \
  "https://192.168.1.111/api/v4/vms/73/poweroff"
```

**⏱️ Timing Note:** **Wait 15-20 seconds** for graceful shutdown to complete before proceeding with other operations.

### Cloning for New Deployments

To create a new cluster from an existing configuration:

```bash
# Clone the directory
cp -r talos-vergeos-automation talos-cluster-2

# Clean old state
cd talos-cluster-2
rm -f terraform.tfstate terraform.tfstate.backup kubeconfig talosconfig *.yaml

# Update VM names in main.tf
sed -i 's/talos-cp-01/talos-cp-02/g' main.tf
sed -i 's/talos-worker-01/talos-worker-02/g' main.tf

# Deploy new cluster
terraform init
terraform apply -var="vergeos_user=admin" -var="vergeos_pass=YourPassword" -auto-approve
```

---

## ⚠️ Troubleshooting Guide

### Issue: Terraform Shows "No Changes" But VMs Are Running

**Symptom:** `terraform apply` reports no changes needed, but VMs are still powered on.

**Cause:** Terraform state is out of sync with actual VM power state.

**Solution:** Use the VergeOS API directly to manage power state:
```bash
curl -k -u "admin:password" -X POST \
  "https://192.168.1.111/api/v4/vms/{vm_id}/poweroff"
```

### Issue: "Connection Refused" During Bootstrap

**Symptom:** `talosctl bootstrap` fails with "connection refused"

**Cause:** Talos API not ready yet after `apply-config`.

**Solution:** Wait 30-60 seconds after applying configuration before bootstrapping:
```bash
talosctl apply-config --nodes $CP_IP --file controlplane.yaml --insecure
sleep 30
talosctl bootstrap
```

### Issue: Nodes Show "NotReady"

**Symptom:** `kubectl get nodes` shows nodes in NotReady state.

**Cause:** CNI (Flannel) or CoreDNS still initializing.

**Solution:** Wait 20-30 seconds. Check pod status:
```bash
kubectl --kubeconfig kubeconfig get pods -n kube-system
```

Ensure `kube-flannel` and `coredns` pods are Running.

### Issue: IP Discovery Times Out

**Symptom:** `get_verge_ip.py` times out waiting for IP.

**Causes:**
1. VM hasn't booted yet
2. DHCP server not responding
3. Network misconfiguration

**Solution:**
```bash
# Check VM status in VergeOS
curl -k -u "admin:password" \
  "https://192.168.1.111/api/v4/vms?filter=name eq 'talos-cp-02'" | jq

# Verify VM is powered on and check console for boot errors
```

### Issue: Terraform CD-ROM Sync Errors

**Symptom:** Terraform fails with "Error syncing disks" and 404 on CD-ROM drive.

**Cause:** CD-ROM drive was removed manually but still exists in Terraform state.

**Solution:** Either:
1. Keep CD-ROM in Terraform config (recommended)
2. Or remove from both actual VM and Terraform config together

---

## 🎯 Production Considerations

### Security Hardening

1. **Remove CD-ROM After Install:**
```bash
# Get CD-ROM drive ID
curl -k -u "admin:password" \
  "https://192.168.1.111/api/v4/machine_drives" | \
  jq '.[] | select(.machine == 94 and .media == "cdrom")'

# Remove it
curl -k -u "admin:password" -X DELETE \
  "https://192.168.1.111/api/v4/machine_drives/{drive_id}"
```

2. **Change Boot Order:**
Update `boot_order` in Terraform from `"c"` to `"d"` after installation.

3. **Enable Talos RBAC:**
Talos v1.12.2 includes RBAC by default. Verify:
```bash
talosctl --talosconfig talosconfig version
```

### High Availability

For production, deploy 3 control plane nodes:

```hcl
resource "vergeio_vm" "talos_cp" {
  count = 3
  name  = "talos-cp-${count.index + 1}"
  # ... rest of configuration
}
```

Update bootstrap to use all control plane IPs:
```bash
talosctl gen config talos-cluster https://10.0.6.166:6443,https://10.0.6.167:6443,https://10.0.6.168:6443
```

### Backup and Recovery

1. **Backup etcd:**
```bash
talosctl --talosconfig talosconfig etcd snapshot /tmp/etcd-backup.db
```

2. **Backup Talos configs:**
Store `controlplane.yaml`, `worker.yaml`, and `talosconfig` in secure version control.

---

## 🏁 Conclusion

You now have a complete, production-ready workflow for deploying Talos Linux Kubernetes clusters on VergeOS. The key takeaways:

1. **Automation is achievable** - From VM provisioning to cluster bootstrap in ~2 minutes
2. **Timing matters** - Wait times are critical for stability (30s after config apply, 30s after bootstrap)
3. **IP discovery is essential** - The `get_verge_ip.py` script bridges the gap between Terraform and Talos
4. **API-first approach** - Both VergeOS and Talos are fully API-driven, enabling complete automation

The combination of VergeOS's high-performance infrastructure and Talos's immutable, security-focused design creates a powerful platform for modern Kubernetes deployments.

---

## 📚 Additional Resources

- [Talos Linux Documentation](https://www.talos.dev/docs/)
- [VergeOS Terraform Provider](https://registry.terraform.io/providers/verge-io/vergeio/latest)
- [Talos Image Factory](https://factory.talos.dev)
- [VergeOS API Documentation](https://docs.verge.io)

---

**Ready to deploy your own immutable Kubernetes infrastructure? Clone the repository and get started:**

```bash
git clone https://github.com/yourusername/talos-vergeos-automation
cd talos-vergeos-automation
terraform init
# Follow the steps above!
```
