# Talos Linux on VergeOS - Automated Deployment

Deploy production-grade Kubernetes clusters on VergeOS using Talos Linux in under 2 minutes.

## 🚀 Quick Start

This repository contains everything you need to deploy immutable, security-hardened Kubernetes clusters on VergeOS infrastructure using Terraform and Talos Linux.

**Total deployment time: ~2 minutes from zero to fully operational cluster**

## 📋 Prerequisites

- **VergeOS Instance**: Running and accessible
- **Terraform**: v1.0+ with VergeOS provider
- **talosctl**: v1.12.2 or compatible
- **kubectl**: For Kubernetes management
- **Python 3**: For IP discovery automation
- **Git**: For cloning this repository

## 🏗️ Architecture

This automation deploys:
- **Control Plane Node**: 4 CPU cores, 8GB RAM
- **Worker Node**: 4 CPU cores, 8GB RAM
- **Talos Linux**: v1.12.2 (immutable OS)
- **Kubernetes**: v1.35.0

## 📦 Installation

### 1. Clone the Repository

```bash
git clone https://github.com/dvvincent/talos-vergeos-automation2.git
cd talos-vergeos-automation2
```

### 2. Configure Credentials

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit with your VergeOS server and credentials
nano terraform.tfvars
```

**Configure the following in `terraform.tfvars`:**
- `vergeos_host` - Your VergeOS server IP or hostname (e.g., "192.168.1.111")
- `vergeos_user` - Your VergeOS username (e.g., "admin")
- `vergeos_pass` - Your VergeOS password
- `talos_image_id` - The ID of your uploaded Talos ISO in VergeOS

**Important:** Never commit `terraform.tfvars` to git - it contains your credentials!

### 3. Set Environment Variables

```bash
export VERGEOS_USER="admin"
export VERGEOS_PASS="YourPassword"
```

### 4. Deploy the Infrastructure

```bash
# Initialize Terraform
terraform init

# Deploy VMs
terraform apply -var="vergeos_user=$VERGEOS_USER" -var="vergeos_pass=$VERGEOS_PASS" -auto-approve
```

**⏱️ Timing:** VM creation takes ~10-15 seconds

### 5. Discover IP Addresses

```bash
# Discover control plane IP (waits up to 5 minutes)
CP_IP=$(python3 scripts/get_verge_ip.py --machine-name talos-cp-02 --timeout 300)
echo "Control Plane IP: $CP_IP"

# Discover worker IP
WORKER_IP=$(python3 scripts/get_verge_ip.py --machine-name talos-worker-02 --timeout 300)
echo "Worker IP: $WORKER_IP"
```

**⏱️ Timing:** IP discovery takes ~5-30 seconds

### 6. Generate Talos Configuration

```bash
# Generate cluster configuration
talosctl gen config talos-cluster-2 https://$CP_IP:6443
```

### 7. Apply Configuration to Nodes

```bash
# Apply control plane configuration
talosctl apply-config --nodes $CP_IP --file controlplane.yaml --insecure

# Apply worker configuration
talosctl apply-config --nodes $WORKER_IP --file worker.yaml --insecure
```

**⚠️ CRITICAL:** Wait 30 seconds after applying configuration before bootstrapping!

```bash
sleep 30
```

### 8. Bootstrap the Cluster

```bash
# Configure talosctl client
talosctl --talosconfig talosconfig config endpoint $CP_IP
talosctl --talosconfig talosconfig config node $CP_IP

# Bootstrap the cluster
talosctl --talosconfig talosconfig bootstrap
```

**⚠️ CRITICAL:** Wait 30 seconds after bootstrap for Kubernetes to initialize!

```bash
sleep 30
```

### 9. Get kubeconfig and Verify

```bash
# Retrieve kubeconfig
talosctl --talosconfig talosconfig kubeconfig .

# Wait for nodes to become Ready
sleep 20

# Verify cluster
kubectl --kubeconfig kubeconfig get nodes -o wide
kubectl --kubeconfig kubeconfig get pods -A
```

## ⏱️ Complete Timing Breakdown

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

**Total: ~2 minutes**

## 🛠️ Managing VMs

### Shutdown VMs

```bash
# Get VM IDs from Terraform state
terraform show | grep "id ="

# Shutdown using VergeOS API
curl -k -u "admin:YourPassword" -X POST \
  "https://192.168.1.111/api/v4/vms/{vm_id}/poweroff"
```

**⏱️ Wait 15-20 seconds** for graceful shutdown.

### Clone for New Deployment

```bash
# Clone directory
cp -r talos-vergeos-automation2 talos-cluster-3

# Clean state
cd talos-cluster-3
rm -f terraform.tfstate* kubeconfig talosconfig *.yaml

# Update VM names in main.tf
sed -i 's/talos-cp-02/talos-cp-03/g' main.tf
sed -i 's/talos-worker-02/talos-worker-03/g' main.tf

# Deploy new cluster
terraform init
terraform apply
```

## 📁 Repository Structure

```
talos-vergeos-automation2/
├── main.tf                    # VM resource definitions
├── provider.tf                # VergeOS provider configuration
├── variables.tf               # Input variables
├── terraform.tfvars.example   # Example configuration (SAFE)
├── .gitignore                 # Excludes sensitive files
├── scripts/
│   └── get_verge_ip.py       # IP discovery automation
└── README.md                  # This file
```

## 🔒 Security Notes

### Files Excluded from Git (via .gitignore)

The following files contain sensitive data and are **never** committed:

- `terraform.tfvars` - Contains your credentials
- `terraform.tfstate*` - May contain sensitive data
- `talosconfig` - Talos cluster admin credentials
- `controlplane.yaml` - Contains cluster secrets
- `worker.yaml` - Contains cluster secrets
- `kubeconfig` - Kubernetes admin credentials
- `.env*` - Environment files
- `*.token`, `*.key`, `*.pem` - Any credential files

### Best Practices

1. **Never commit credentials** - Use `terraform.tfvars.example` as a template
2. **Use environment variables** - For CI/CD pipelines
3. **Rotate secrets regularly** - Regenerate Talos configs periodically
4. **Backup securely** - Store `talosconfig` and `kubeconfig` in a password manager
5. **Use RBAC** - Limit access to Kubernetes resources

## ⚠️ Troubleshooting

### Connection Refused During Bootstrap

**Symptom:** `talosctl bootstrap` fails with "connection refused"

**Solution:** Wait 30-60 seconds after `apply-config` before bootstrapping.

### Nodes Show NotReady

**Symptom:** `kubectl get nodes` shows NotReady status

**Solution:** Wait 20-30 seconds for CNI (Flannel) to initialize. Check pod status:
```bash
kubectl --kubeconfig kubeconfig get pods -n kube-system
```

### IP Discovery Times Out

**Symptom:** `get_verge_ip.py` times out

**Solution:** 
1. Verify VM is powered on
2. Check DHCP server is responding
3. Verify network configuration in VergeOS

### Terraform State Sync Issues

**Symptom:** Terraform shows "No changes" but VMs are running

**Solution:** Use VergeOS API directly:
```bash
curl -k -u "admin:password" -X POST \
  "https://192.168.1.111/api/v4/vms/{vm_id}/poweroff"
```

## 📚 Additional Resources

- [Full Blog Post](BLOG_POST.md) - Complete deployment guide with detailed explanations
- [Talos Linux Documentation](https://www.talos.dev/docs/)
- [VergeOS Terraform Provider](https://registry.terraform.io/providers/verge-io/vergeio/latest)
- [Talos Image Factory](https://factory.talos.dev)

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

**Important:** Never commit files containing credentials or secrets!

## 📝 License

MIT License - See LICENSE file for details

## 🙏 Acknowledgments

- Talos Linux team for the amazing immutable OS
- VergeOS for the powerful hyperconverged platform
- The Kubernetes community

---

**Ready to deploy immutable Kubernetes infrastructure? Follow the Quick Start guide above!**
