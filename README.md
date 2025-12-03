 # HA Kubernetes Cluster on AWS (Terraform + Ansible)

[![Deploy HA Kubernetes Cluster](https://github.com/OmarFathy22/HA-Kubernetes-Cluster-on-AWS-using-Terraform/actions/workflows/deploy-k8s-cluster.yml/badge.svg?branch=platform)](https://github.com/OmarFathy22/HA-Kubernetes-Cluster-on-AWS-using-Terraform/actions/workflows/deploy-k8s-cluster.yml)
[![Destroy Cluster](https://github.com/OmarFathy22/HA-Kubernetes-Cluster-on-AWS-using-Terraform/actions/workflows/destroy-k8s-cluster.yml/badge.svg?branch=platform)](https://github.com/OmarFathy22/HA-Kubernetes-Cluster-on-AWS-using-Terraform/actions/workflows/destroy-k8s-cluster.yml)

Production-ready, highly available Kubernetes cluster on AWS using only Terraform + Ansible (no EKS, no managed services).

---

## 🎉 What's New: Ansible Integration

**v2.0 - Complete Refactor from Bash Scripts to Ansible**

| Before (v1.0) | After (v2.0) |
|---------------|--------------|
| ❌ Bash scripts in EC2 user_data | ✅ Ansible playbooks & roles |
| ❌ Can't re-run without recreating | ✅ Idempotent - run anytime |
| ❌ Hard to debug and maintain | ✅ Clear, readable YAML |
| ❌ No upgrade path | ✅ In-place Kubernetes upgrades |
| ❌ Manual IP management | ✅ Auto-generated inventory |

**Key Benefits:**
- 🔄 **Idempotent**: Safe to run multiple times
- 🎯 **Maintainable**: Easy-to-read YAML instead of bash
- 🚀 **Upgradeable**: Update Kubernetes without destroying cluster
- 🔧 **Testable**: Run specific tasks with tags
- 📊 **Professional**: Industry-standard automation

---

## 🏗️ Architecture

```
                    Internet Gateway
                           |
              Network Load Balancer (API :6443)
                           |
        ┌──────────────────┼──────────────────┐
        │                  │                  │
    Master-01          Master-02         Master-03
    (Leader)          (Follower)        (Follower)
        │                  │                  │
        └──────────────────┼──────────────────┘
                           |
                    etcd HA Cluster
                           |
                ┌──────────┴──────────┐
                │                     │
            Worker-01             Worker-02
                
                S3 Bucket (Bootstrap Coordination)
```

**Components:**
- 3 Master Nodes (HA control plane)
- 2 Worker Nodes (workloads)
- Network Load Balancer (single API endpoint)
- S3 Bucket (join token coordination)
- Calico CNI (pod networking)

---

## 📋 Prerequisites

```bash
# Required tools
terraform --version  # >= 1.7
ansible --version    # >= 2.15
aws --version        # >= 2.x
jq --version         # for inventory generation

# AWS
- AWS Account with IAM permissions
- EC2 key pair for SSH access
- AWS CLI configured (aws configure)
```

**Install tools:**
```bash
# Ubuntu/Debian
sudo apt install -y terraform ansible awscli jq

# macOS
brew install terraform ansible awscli jq
```

---

## 🚀 Quick Start (3 Simple Steps)

### Step 1: Deploy Infrastructure with Terraform

```bash
cd terraform
terraform init
terraform apply -auto-approve

# Wait ~5 minutes for EC2 instances
```

### Step 2: Generate Ansible Inventory

```bash
cd ../ansible
chmod +x generate-inventory.sh
./generate-inventory.sh

# Edit SSH key path in generated inventory
nano inventory/hosts.ini
# Update: ansible_ssh_private_key_file=~/.ssh/your-key.pem
```

### Step 3: Deploy Kubernetes with Ansible

```bash
ansible-playbook playbooks/site.yml

# Total time: ~40 minutes
# ✓ Prepare nodes (15-20 min)
# ✓ Initialize first master (5-10 min)
# ✓ Join additional masters (5 min)
# ✓ Join workers (5 min)
```

### Access Your Cluster

```bash
# Get master IP
MASTER_IP=$(grep master01 inventory/hosts.ini | awk '{print $2}' | cut -d'=' -f2)

# Copy kubeconfig
scp -i ~/.ssh/your-key.pem ubuntu@${MASTER_IP}:/root/.kube/config ~/.kube/config

# Verify
kubectl get nodes
```

**Expected output:**
```
NAME       STATUS   ROLES           AGE   VERSION
master01   Ready    control-plane   10m   v1.33.0
master02   Ready    control-plane   8m    v1.33.0
master03   Ready    control-plane   6m    v1.33.0
worker01   Ready    worker          4m    v1.33.0
worker02   Ready    worker          4m    v1.33.0
```

---

## 📁 Project Structure

```
.
├── terraform/                 # Infrastructure (AWS resources)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf            # Used by Ansible
│   └── modules/
│       ├── vpc/
│       ├── security_groups/
│       ├── load_balancer/
│       ├── s3/
│       └── ec2/
│
└── ansible/                   # Configuration (Kubernetes setup)
    ├── ansible.cfg
    ├── generate-inventory.sh  # Auto-creates inventory from Terraform
    ├── inventory/
    │   ├── hosts.ini         # Generated automatically
    │   └── group_vars/
    │       ├── all.yml       # Global variables (K8s version, LB DNS)
    │       ├── masters.yml
    │       └── workers.yml
    ├── playbooks/
    │   └── site.yml          # Main playbook
    └── roles/
        ├── common/           # Setup all nodes
        ├── kubernetes-master/ # Setup masters
        ├── kubernetes-worker/ # Setup workers
        
```

---

## 🔧 Common Operations

### Add More Workers

```bash
# Update Terraform
cd terraform
terraform apply -var="worker_count=4"

# Regenerate inventory
cd ../ansible
./generate-inventory.sh

# Deploy new workers only
ansible-playbook playbooks/site.yml --limit worker03,worker04 --tags prepare,workers
```

### Run Specific Tasks

```bash
# Only prepare nodes
ansible-playbook playbooks/site.yml --tags prepare

# Only setup masters
ansible-playbook playbooks/site.yml --tags masters

# Only join workers
ansible-playbook playbooks/site.yml --tags workers
```

### Re-run Deployment (Safe!)

```bash
# Ansible is idempotent - safe to run multiple times
ansible-playbook playbooks/site.yml

# It will:
# ✓ Skip already completed tasks
# ✓ Fix any configuration drift
# ✓ Complete any failed tasks
```

---

## 🐛 Troubleshooting

### Test SSH Connectivity

```bash
# Test all nodes
ansible all -m ping

# If it fails, check:
chmod 400 ~/.ssh/your-key.pem
ssh -i ~/.ssh/your-key.pem ubuntu@<master-ip>
```

### Debug Ansible Execution

```bash
# Verbose output
ansible-playbook playbooks/site.yml -vvv

# Run on specific node
ansible-playbook playbooks/site.yml --limit master02

# Start from specific task
ansible-playbook playbooks/site.yml --start-at-task="Install containerd"
```

### Check Node Status

```bash
# SSH to node
ssh -i ~/.ssh/your-key.pem ubuntu@<node-ip>

# Check services
sudo systemctl status kubelet
sudo systemctl status containerd

# Check logs
sudo journalctl -u kubelet -f
```

---

## 🧹 Cleanup

```bash
cd terraform
terraform destroy -auto-approve
```

---

## 📊 Specifications

**Kubernetes**: v1.33 (latest stable)  
**Container Runtime**: containerd with systemd cgroups  
**CNI Plugin**: Calico v3.27.3  
**Instance Type**: t3.medium (2 vCPU, 4GB RAM)  
**OS**: Ubuntu 22.04 LTS  
**Storage**: 20GB per instance  

---

## 🎯 Why Ansible Over Bash Scripts?

### Bash Scripts (v1.0)
```bash
#!/bin/bash
apt-get update || true
kubeadm init ... > /tmp/out 2>&1 || (cat /tmp/out; exit 1)
# If fails at line 100, destroy and start over
```

### Ansible (v2.0)
```yaml
- name: Update packages
  apt:
    update_cache: yes
  retries: 3

- name: Initialize cluster
  command: kubeadm init ...
  when: not already_initialized
  register: result
```

**Result:** Readable, maintainable, and re-runnable automation.

---


## 📝 License

MIT License - Feel free to use and modify

---

## 🤝 Contributing

Contributions welcome! Please open an issue or submit a PR.

---

**Built with ❤️ using Terraform, Ansible, and Kubernetes**
