# HA Kubernetes Cluster on AWS (Automated with Terraform)

Production-ready, highly available Kubernetes cluster deployed on AWS using Terraform with fully automated bootstrap via EC2 user data scripts.

## 🏗️ Architecture

```
                         Internet Gateway
                                |
                    ┌───────────┴───────────┐
                    │                       │
            Public Subnet 1         Public Subnet 2
                    │                       │
        ┌───────────┴───────────┐           │
        │  Network Load Balancer│           │
        │    (API Server :6443) │           │
        └───────────┬───────────┘           │
                    │                       │
        ┌───────────┼───────────────────────┼───────────┐
        │           │                       │           │
        │           ▼                       ▼           ▼
        │      Master-01              Master-02    Master-03
        │      (Leader)               (Follower)  (Follower)
        │           │                       │           │
        │           └───────────┬───────────┘           │
        │                       │                       │
        │                   etcd Cluster                │
        │                       │                       │
        │           ┌───────────┴───────────┐           │
        │           ▼                       ▼           │
        │      Worker-01                Worker-02       │
        │                                               │
        │                S3 Bucket                      │
        │         (Bootstrap Coordination)              │
        └───────────────────────────────────────────────┘
```

### Key Components:
- **3 Master Nodes**: HA control plane with distributed etcd
- **2 Worker Nodes**: Application workload nodes  
- **Network Load Balancer**: Single API endpoint for cluster access
- **S3 Bucket**: Coordination layer for automated join credentials
- **Calico CNI**: Pod networking (192.168.0.0/16)



---
## 🚀 Why Use This Solution?
- Instant HA Deployment – Launch a highly available Kubernetes cluster in minutes, fully automated.
- Microservices Ready – Provides a stable foundation for deploying and managing microservices.
- Cost-Effective – Enterprise-grade Kubernetes without expensive managed services.
- Cloud Flexibility – Run on AWS, minimizing on-premise infrastructure and scaling effortlessly.
- Easy & Transparent – Clear documentation and scripts for teams of any experience level.

---



### Prerequisites
- AWS Account with appropriate permissions
- Terraform >= 1.0
- AWS CLI configured
- EC2 key pair

### Deploy

```bash
# Clone repository
git clone <your-repo>
cd <your-repo>

# Initialize Terraform
terraform init

# Review plan
terraform plan

# Deploy infrastructure
terraform apply

# Wait 15-20 minutes for automated cluster bootstrap
```

### Access Cluster

```bash
# Get Master-01 IP
terraform output master_public_ips

# SSH to Master-01
ssh -i your-key.pem ubuntu@<master-01-ip>

# Verify cluster
sudo kubectl get nodes
```

---

## 🔧 Phase 1: Infrastructure as Code

### Terraform Modules

```
.
├── main.tf                    # Root configuration
├── modules/
│   ├── vpc/                   # Network infrastructure
│   ├── security_groups/       # Firewall rules
│   ├── load_balancer/         # NLB for API server
│   ├── s3/                    # Bootstrap bucket
│   └── ec2/                   # Compute resources + user data
```



### Key Configuration

```hcl
module "ec2" {
  source = "./modules/ec2"
  
  master_count = 3
  worker_count = 2
  
  # Scripts are injected via cloud-init
  # Gzip-compressed to fit 16KB user data limit
}
```

---

## ⚙️ Phase 2: Automated Bootstrap Scripts

### The Three Scripts

1. **`common-init.sh`** - Runs on ALL nodes
   - System updates & package installation
   - Containerd setup with systemd cgroups
   - Kubernetes components (kubeadm, kubelet, kubectl)
   - `/etc/hosts` configuration for LB DNS resolution

2. **`master-init.sh`** - Runs on master nodes
   - **Leader (Master-01)**:
     - Initializes cluster with `kubeadm init`
     - Uploads private IP to S3
     - Extracts join tokens & uploads to S3
     - Installs Calico CNI
   - **Followers (Master-02/03)**:
     - Wait for leader via S3 polling
     - Download join credentials
     - Join as control plane nodes

3. **`worker-init.sh`** - Runs on worker nodes
   - Waits for 2+ masters to be ready (HA guarantee)
   - Downloads worker join command from S3
   - Joins cluster as worker node

### Bootstrap Flow

```
┌─────────────┐
│ Master-01   │  1. kubeadm init
│  (Leader)   │  2. Upload IP → S3
└──────┬──────┘  3. Upload join commands → S3
       │         4. Create ready flag → S3
       ▼
    ┌──────────────────────────────┐
    │       S3 Coordination        │
    │  ├─ master01-private-ip.txt  │
    │  ├─ join-commands/           │
    │  │   ├─ master-join.sh       │
    │  │   └─ worker-join.sh       │
    │  └─ flags/                   │
    │      └─ master01-ready.flag  │
    └──────────────────────────────┘
       │                      │
       ▼                      ▼
┌──────────────┐      ┌──────────────┐
│  Master-02   │      │  Master-03   │
│ (Follower)   │      │ (Follower)   │
└──────┬───────┘      └──────┬───────┘
       │                     │
       └──────────┬──────────┘
                  ▼
          ┌───────────────┐
          │   Workers     │
          │  (Wait for    │
          │   2 masters)  │
          └───────────────┘
```



## 🔍 Verification

```bash
# On Master-01
kubectl get nodes
# Expected: 5 nodes (3 masters, 2 workers) - all Ready

kubectl get pods -A
# Expected: All system pods Running

kubectl cluster-info
# Expected: API server responding via LB DNS
```

---


## 🐛 Troubleshooting

### Check Bootstrap Progress

```bash
# SSH to any node
ssh -i key.pem ubuntu@<node-ip>

# View logs
sudo tail -f /var/log/k8s-common-init.log
sudo tail -f /var/log/k8s-master-init.log  # masters only
sudo tail -f /var/log/k8s-worker-init.log  # workers only

# Check S3 coordination
aws s3 ls s3://your-bucket/flags/
aws s3 ls s3://your-bucket/join-commands/
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Master-01 init fails | Check `/tmp/kubeadm-init-output.txt` |
| Followers can't join | Verify S3 bucket permissions |
| Workers timeout | Check if 2+ masters are ready |
| kubectl not found | Scripts didn't run - check cloud-init logs |

---

## 🧹 Cleanup

```bash
terraform destroy
```

**Note**: S3 bucket may need manual cleanup if versioning is enabled or it's not empty
---

### Kubernetes Version
- **v1.33** (latest stable)
- Containerd runtime with systemd cgroups
- Calico CNI v3.27.3

### AWS Resources
- **Instance Type**: t3.small (2 vCPU, 2GB RAM)
- **OS**: Ubuntu 22.04 LTS
- **Storage**: 20GB (masters), 20GB (workers)
- **Networking**: Public subnets (can be adapted for private)

---


## ⭐ Acknowledgments

Built with Terraform, Kubernetes, and AWS. Automated bootstrap inspired by cloud-native best practices.

