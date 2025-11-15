#!/bin/bash
################################################################################
# master-init.sh - Initialize Kubernetes master nodes
# This script runs on ALL master nodes with different logic for leader/followers
################################################################################

set -e
exec > >(tee -a /var/log/k8s-master-init.log)
exec 2>&1

echo "=========================================="
echo "Starting master-init.sh"
echo "Hostname: ${HOSTNAME}"
echo "IS_LEADER: ${IS_LEADER}"
echo "LB_DNS: ${LB_DNS}"
echo "BOOTSTRAP_BUCKET: ${BOOTSTRAP_BUCKET}"
echo "Timestamp: $(date)"
echo "=========================================="

# Helper function: Wait for S3 object
wait_for_s3_object() {
    local bucket=$1
    local key=$2
    local max_attempts=40
    local attempt=1
    
    echo "[WAIT] Checking for s3://$bucket/$key"
    
    while [ $attempt -le $max_attempts ]; do
        echo "[WAIT] Attempt $attempt/$max_attempts"
        
        if aws s3 ls "s3://$bucket/$key" 2>/dev/null; then
            echo "[SUCCESS] Found s3://$bucket/$key"
            return 0
        fi
        
        sleep 30
        attempt=$((attempt + 1))
    done
    
    echo "[ERROR] Timeout waiting for s3://$bucket/$key"
    return 1
}

# Helper function: Wait for common-init to complete
wait_for_common_init() {
    echo "[WAIT] Waiting for common-init.sh to complete..."
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if [ -f /tmp/common-init-complete ]; then
            echo "[SUCCESS] common-init.sh completed"
            return 0
        fi
        
        echo "[WAIT] Attempt $attempt/$max_attempts - waiting for common-init..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    echo "[ERROR] common-init.sh did not complete in time"
    return 1
}

# Wait for common-init to finish
if ! wait_for_common_init; then
    echo "[ERROR] Cannot proceed without common-init completion"
    exit 1
fi

################################################################################
# LEADER PATH (Master01)
################################################################################
if [ "${IS_LEADER}" = "true" ]; then
    echo "=========================================="
    echo "LEADER NODE - Initializing Kubernetes Cluster"
    echo "=========================================="
    
    # STEP 1: Wait for Load Balancer to be reachable
    echo "[STEP 1] Waiting for Load Balancer to be reachable..."
    max_attempts=30
    attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "[WAIT] Attempt $attempt/$max_attempts - Testing LB connectivity..."
        
        # Try to connect to LB on port 6443 (will fail initially, that's OK)
        if timeout 5 bash -c "echo > /dev/tcp/${LB_DNS}/6443" 2>/dev/null; then
            echo "[INFO] LB is reachable (or port is open)"
            break
        fi
        
        # After several attempts, proceed anyway (LB might not respond until API server is up)
        if [ $attempt -ge 10 ]; then
            echo "[INFO] Proceeding with initialization (LB will be available after API server starts)"
            break
        fi
        
        sleep 10
        attempt=$((attempt + 1))
    done
    
    # STEP 2: Get own private IP and upload to S3
    echo "[STEP 2] Getting private IP and uploading to S3..."
    #PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
    
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
         -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
         http://169.254.169.254/latest/meta-data/local-ipv4)
    
    if [ -z "$${PRIVATE_IP}" ]; then
        echo "[ERROR] Failed to get private IP from metadata service"
        exit 1
    fi
    
    echo "[INFO] Private IP: $${PRIVATE_IP}"
    echo -n "$${PRIVATE_IP}" | aws s3 cp - s3://${BOOTSTRAP_BUCKET}/master01-private-ip.txt
    echo "[SUCCESS] Private IP uploaded to S3"
    
    # STEP 3: Initialize Kubernetes cluster
    echo "[STEP 3] Initializing Kubernetes cluster with kubeadm..."
    
    kubeadm init \
      --control-plane-endpoint "${LB_DNS}:6443" \
      --upload-certs \
      --pod-network-cidr=192.168.0.0/16 \
      2>&1 | tee /tmp/kubeadm-init-output.txt
    
    if [ $${PIPESTATUS[0]} -ne 0 ]; then
        echo "[ERROR] kubeadm init failed!"
        cat /tmp/kubeadm-init-output.txt
        exit 1
    fi
    
    echo "[SUCCESS] Kubernetes cluster initialized!"
    
    # STEP 4: Configure kubectl for root user
    echo "[STEP 4] Configuring kubectl for root user..."
    mkdir -p /root/.kube
    cp -f /etc/kubernetes/admin.conf /root/.kube/config
    chown root:root /root/.kube/config
    export KUBECONFIG=/etc/kubernetes/admin.conf
    echo "[SUCCESS] kubectl configured"
    
    # STEP 5: Extract join tokens and commands
    echo "[STEP 5] Extracting join credentials..."
    
    # Extract token
    TOKEN=$(grep -oP 'token \K[^\s]+' /tmp/kubeadm-init-output.txt | head -1)
    
    # Extract CA cert hash
    CA_HASH=$(grep -oP 'discovery-token-ca-cert-hash \K[^\s]+' /tmp/kubeadm-init-output.txt | head -1)
    
    # Extract certificate key
    CERT_KEY=$(grep -oP 'certificate-key \K[^\s]+' /tmp/kubeadm-init-output.txt | head -1)
    
    if [ -z "$${TOKEN}" ] || [ -z "$${CA_HASH}" ] || [ -z "$${CERT_KEY}" ]; then
        echo "[ERROR] Failed to extract join credentials!"
        echo "TOKEN: $${TOKEN}"
        echo "CA_HASH: $${CA_HASH}"
        echo "CERT_KEY: $${CERT_KEY}"
        exit 1
    fi
    
    echo "[INFO] Extracted credentials:"
    echo "  TOKEN: $${TOKEN}"
    echo "  CA_HASH: $${CA_HASH}"
    echo "  CERT_KEY: $${CERT_KEY:0:20}..."
    
    # STEP 6: Create join command scripts
    echo "[STEP 6] Creating join command scripts..."
    
    # Master join command
    cat > /tmp/master-join.sh <<MASTEREOF
#!/bin/bash
kubeadm join ${LB_DNS}:6443 \\
  --token $${TOKEN} \\
  --discovery-token-ca-cert-hash $${CA_HASH} \\
  --control-plane \\
  --certificate-key $${CERT_KEY}
MASTEREOF
    
    # Worker join command
    cat > /tmp/worker-join.sh <<WORKEREOF
#!/bin/bash
kubeadm join ${LB_DNS}:6443 \\
  --token $${TOKEN} \\
  --discovery-token-ca-cert-hash $${CA_HASH}
WORKEREOF
    
    chmod +x /tmp/master-join.sh /tmp/worker-join.sh
    
    # STEP 7: Upload join commands to S3
    echo "[STEP 7] Uploading join commands to S3..."
    aws s3 cp /tmp/master-join.sh s3://${BOOTSTRAP_BUCKET}/join-commands/master-join.sh
    aws s3 cp /tmp/worker-join.sh s3://${BOOTSTRAP_BUCKET}/join-commands/worker-join.sh
    aws s3 cp /etc/kubernetes/admin.conf s3://${BOOTSTRAP_BUCKET}/configs/admin.conf
    echo "[SUCCESS] Join commands uploaded to S3"
    
    # STEP 8: Install CNI (Calico)
    echo "[STEP 8] Installing Calico CNI..."
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml
    echo "[SUCCESS] Calico CNI installed"
    
    # STEP 9: Wait for nodes to be ready
    echo "[STEP 9] Waiting for node to be ready..."
    max_attempts=30
    attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if kubectl get nodes | grep -q "Ready"; then
            echo "[SUCCESS] Node is ready!"
            kubectl get nodes
            break
        fi
        
        echo "[WAIT] Attempt $attempt/$max_attempts - Node not ready yet..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    # STEP 10: Create ready flag
    echo "[STEP 10] Creating ready flag in S3..."
    echo "ready" | aws s3 cp - s3://${BOOTSTRAP_BUCKET}/flags/master01-ready.flag
    echo "[SUCCESS] Master01 ready flag created"
    
    echo "=========================================="
    echo "LEADER INITIALIZATION COMPLETE!"
    echo "Cluster is ready for additional nodes to join"
    echo "=========================================="

################################################################################
# FOLLOWER PATH (Master02, Master03)
################################################################################
else
    echo "=========================================="
    echo "FOLLOWER NODE - Joining Kubernetes Cluster"
    echo "=========================================="
    
    # STEP 1: Wait for master01 to be ready
    echo "[STEP 1] Waiting for master01 to be ready..."
    
    if ! wait_for_s3_object "${BOOTSTRAP_BUCKET}" "flags/master01-ready.flag"; then
        echo "[ERROR] Master01 is not ready!"
        exit 1
    fi
    
    echo "[SUCCESS] Master01 is ready, proceeding to join..."
    
    # STEP 2: Download master join command
    echo "[STEP 2] Downloading master join command from S3..."
    
    if ! aws s3 cp s3://${BOOTSTRAP_BUCKET}/join-commands/master-join.sh /tmp/master-join.sh; then
        echo "[ERROR] Failed to download master join command"
        exit 1
    fi
    
    chmod +x /tmp/master-join.sh
    echo "[SUCCESS] Master join command downloaded"
    
    # STEP 3: Execute join command
    echo "[STEP 3] Joining cluster as control plane..."
    
    if ! /tmp/master-join.sh 2>&1 | tee /tmp/kubeadm-join-output.txt; then
        echo "[ERROR] Failed to join cluster!"
        cat /tmp/kubeadm-join-output.txt
        exit 1
    fi
    
    echo "[SUCCESS] Successfully joined cluster as control plane!"
    
    # STEP 4: Configure kubectl
    echo "[STEP 4] Configuring kubectl..."
    mkdir -p /root/.kube
    
    # Download admin.conf from S3
    aws s3 cp s3://${BOOTSTRAP_BUCKET}/configs/admin.conf /root/.kube/config
    chown root:root /root/.kube/config
    export KUBECONFIG=/root/.kube/config
    
    echo "[SUCCESS] kubectl configured"
    
    # STEP 5: Verify node joined
    echo "[STEP 5] Verifying node status..."
    sleep 10
    kubectl get nodes
    
    # STEP 6: Create ready flag for this node
    echo "[STEP 6] Creating ready flag in S3..."
    NODE_NAME=$(hostname)
    echo "ready" | aws s3 cp - s3://${BOOTSTRAP_BUCKET}/flags/$${NODE_NAME}-ready.flag
    echo "[SUCCESS] $${NODE_NAME} ready flag created"
    
    echo "=========================================="
    echo "FOLLOWER NODE JOIN COMPLETE!"
    echo "=========================================="
fi

################################################################################
# FINAL STATUS
################################################################################
echo ""
echo "=========================================="
echo "MASTER NODE INITIALIZATION SUMMARY"
echo "=========================================="
echo "Hostname: $(hostname)"
echo "Role: Master (Leader: ${IS_LEADER})"
echo "Timestamp: $(date)"
echo ""
echo "Cluster nodes:"
kubectl get nodes -o wide 2>/dev/null || echo "kubectl not yet available"
echo ""
echo "Cluster pods:"
kubectl get pods -A 2>/dev/null || echo "kubectl not yet available"
echo "=========================================="

exit 0