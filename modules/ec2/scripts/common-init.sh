#!/bin/bash
################################################################################
# common-init.sh - Base initialization for all Kubernetes nodes
# This script runs on ALL nodes (masters and workers)
################################################################################

set -e
exec > >(tee -a /var/log/k8s-common-init.log)
exec 2>&1

echo "=========================================="
echo "Starting common-init.sh"
echo "Hostname: ${HOSTNAME}"
echo "IS_LEADER: ${IS_LEADER}"
echo "LB_DNS: ${LB_DNS}"
echo "BOOTSTRAP_BUCKET: ${BOOTSTRAP_BUCKET}"
echo "Timestamp: $(date)"
echo "=========================================="


################################################################################
#  Install aws CLI v2
################################################################################
echo "[STEP] Installing AWS CLI v2"
apt-get install -y unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip

# Helper function: Wait for S3 object to exist
wait_for_s3_object() {
    local bucket=$1
    local key=$2
    local max_attempts=40  # 40 * 30s = 20 minutes
    local attempt=1
    
    echo "[WAIT] Checking for s3://$bucket/$key"
    
    while [ $attempt -le $max_attempts ]; do
        echo "[WAIT] Attempt $attempt/$max_attempts"
        
        if aws s3 ls "s3://$bucket/$key" 2>/dev/null; then
            echo "[SUCCESS] Found s3://$bucket/$key"
            return 0
        fi
        
        echo "[WAIT] Not found yet, waiting 30 seconds..."
        sleep 30
        attempt=$((attempt + 1))
    done
    
    echo "[ERROR] Timeout waiting for s3://$bucket/$key after $max_attempts attempts"
    return 1
}

# Helper function: Retry command with exponential backoff
retry_command() {
    local max_attempts=5
    local attempt=1
    local delay=5
    
    while [ $${attempt} -le $${max_attempts} ]; do
        echo "[RETRY] Attempt $${attempt}/$${max_attempts}: $@"
        
        if "$@"; then
            echo "[SUCCESS] Command succeeded: $@"
            return 0
        fi
        
        echo "[WARN] Command failed, waiting $${delay}s before retry..."
        sleep $${delay}
        delay=$(($${delay} * 2))
        attempt=$(($${attempt} + 1))
    done
    
    echo "[ERROR] Command failed after $${max_attempts} attempts: $@"
    return 1
}

################################################################################
# STEP 1: Set Hostname
################################################################################
echo "[STEP 1] Setting hostname to ${HOSTNAME}"
hostnamectl set-hostname ${HOSTNAME}
echo "127.0.0.1 ${HOSTNAME}" >> /etc/hosts
echo "[SUCCESS] Hostname set to $(hostname)"

################################################################################
# STEP 2: Configure /etc/hosts for Load Balancer DNS resolution
################################################################################
echo "[STEP 2] Configuring /etc/hosts for Load Balancer DNS"

if [ "${IS_LEADER}" = "true" ]; then
    # Master01 (Leader): LB DNS resolves to localhost
    echo "127.0.0.1 ${LB_DNS}" >> /etc/hosts
    echo "[SUCCESS] Leader node: ${LB_DNS} -> 127.0.0.1"
else
    # All other nodes: Wait for Master01's private IP, then resolve LB DNS to it
    echo "[INFO] Non-leader node: Waiting for Master01 private IP from S3..."
    
    if wait_for_s3_object "${BOOTSTRAP_BUCKET}" "master01-private-ip.txt"; then
        MASTER01_IP=$(aws s3 cp s3://${BOOTSTRAP_BUCKET}/master01-private-ip.txt - 2>/dev/null | tr -d '[:space:]')
        
        if [ -z "$${MASTER01_IP}" ]; then
            echo "[ERROR] Master01 IP is empty!"
            exit 1
        fi
        
        echo "$${MASTER01_IP} ${LB_DNS}" >> /etc/hosts
        echo "[SUCCESS] Non-leader node: ${LB_DNS} -> $${MASTER01_IP}"
    else
        echo "[ERROR] Failed to get Master01 private IP from S3"
        exit 1
    fi
fi

# Verify /etc/hosts configuration
echo "[VERIFY] Current /etc/hosts configuration:"
cat /etc/hosts

################################################################################
# STEP 3: Update system packages
################################################################################
echo "[STEP 3] Updating system packages"
retry_command apt-get update
retry_command apt-get upgrade -y
echo "[SUCCESS] System packages updated"

################################################################################
# STEP 4: Disable swap
################################################################################
echo "[STEP 4] Disabling swap"
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab
echo "[SUCCESS] Swap disabled"

################################################################################
# STEP 5: Load required kernel modules
################################################################################
echo "[STEP 5] Loading kernel modules"

cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

echo "[SUCCESS] Kernel modules loaded"

################################################################################
# STEP 6: Configure sysctl parameters
################################################################################
echo "[STEP 6] Configuring sysctl parameters"

cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system
echo "[SUCCESS] Sysctl parameters configured"


################################################################################
# STEP 7: Install containerd
################################################################################
echo "[STEP 7] Installing containerd"

retry_command apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

retry_command apt-get update
retry_command apt-get install -y containerd.io

echo "[SUCCESS] Containerd installed"

################################################################################
# STEP 8: Configure containerd
################################################################################
echo "[STEP 8] Configuring containerd"

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

echo "[SUCCESS] Containerd configured and started"

################################################################################
# STEP 9: Install Kubernetes components
################################################################################
echo "[STEP 9] Installing Kubernetes components"

retry_command apt-get update
retry_command apt-get install -y apt-transport-https ca-certificates curl gpg

mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" > /etc/apt/sources.list.d/kubernetes.list

retry_command apt-get update
retry_command apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet

echo "[SUCCESS] Kubernetes components installed"

################################################################################
# STEP 10: Verify installations
################################################################################
echo "[STEP 10] Verifying installations"

echo "Containerd version:"
containerd --version

echo "Kubeadm version:"
kubeadm version

echo "Kubelet version:"
kubelet --version

echo "Kubectl version:"
kubectl version --client

################################################################################
# COMPLETION
################################################################################
echo "=========================================="
echo "common-init.sh completed successfully!"
echo "Timestamp: $(date)"
echo "=========================================="

# Create a marker file to indicate common-init is complete
touch /tmp/common-init-complete

exit 0