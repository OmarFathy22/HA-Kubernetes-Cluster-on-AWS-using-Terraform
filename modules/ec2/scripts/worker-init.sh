#!/bin/bash
################################################################################
# worker-init.sh - Initialize Kubernetes worker nodes
# This script runs on ALL worker nodes
################################################################################

set -e
exec > >(tee -a /var/log/k8s-worker-init.log)
exec 2>&1

echo "=========================================="
echo "Starting worker-init.sh"
echo "Hostname: ${HOSTNAME}"
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
# STEP 1: Wait for at least 2 master nodes to be ready
################################################################################
echo "[STEP 1] Waiting for master nodes to be ready..."
echo "[INFO] Workers should join only after at least 2 masters are ready for HA"

masters_ready=0
required_masters=2
max_attempts=60
attempt=1

while [ $${attempt} -le $${max_attempts} ]; do
    echo "[WAIT] Attempt $${attempt}/$${max_attempts} - Checking master readiness..."
    
    masters_ready=0
    
    # Check master01
    if aws s3 ls s3://${BOOTSTRAP_BUCKET}/flags/master01-ready.flag 2>/dev/null; then
        echo "[INFO] ✓ master01 is ready"
        masters_ready=$(($${masters_ready} + 1))
    fi
    
    # Check master02
    if aws s3 ls s3://${BOOTSTRAP_BUCKET}/flags/master02-ready.flag 2>/dev/null || \
       aws s3 ls "s3://${BOOTSTRAP_BUCKET}/flags/" | grep -q "master-02-ready.flag" 2>/dev/null || \
       aws s3 ls "s3://${BOOTSTRAP_BUCKET}/flags/" | grep -q "k8s-master-2-ready.flag" 2>/dev/null; then
        echo "[INFO] ✓ master02 is ready"
        masters_ready=$(($${masters_ready} + 1))
    fi
    
    # Check master03
    if aws s3 ls s3://${BOOTSTRAP_BUCKET}/flags/master03-ready.flag 2>/dev/null || \
       aws s3 ls "s3://${BOOTSTRAP_BUCKET}/flags/" | grep -q "master-03-ready.flag" 2>/dev/null || \
       aws s3 ls "s3://${BOOTSTRAP_BUCKET}/flags/" | grep -q "k8s-master-3-ready.flag" 2>/dev/null; then
        echo "[INFO] ✓ master03 is ready"
        masters_ready=$(($${masters_ready} + 1))
    fi
    
    echo "[INFO] Masters ready: $${masters_ready}/$${required_masters}"
    
    if [ $${masters_ready} -ge $${required_masters} ]; then
        echo "[SUCCESS] Sufficient masters are ready ($${masters_ready}/$${required_masters})"
        break
    fi
    
    # After 20 minutes, proceed with just master01 if available
    if [ $${attempt} -ge 40 ] && [ $${masters_ready} -ge 1 ]; then
        echo "[WARN] Proceeding with only $${masters_ready} master(s) ready (timeout reached)"
        break
    fi
    
    sleep 30
    attempt=$(($${attempt} + 1))
done

if [ $${masters_ready} -eq 0 ]; then
    echo "[ERROR] No master nodes are ready! Cannot join cluster."
    exit 1
fi

################################################################################
# STEP 2: Download worker join command from S3
################################################################################
echo "[STEP 2] Downloading worker join command from S3..."

if ! wait_for_s3_object "${BOOTSTRAP_BUCKET}" "join-commands/worker-join.sh"; then
    echo "[ERROR] Worker join command not found in S3"
    exit 1
fi

if ! aws s3 cp s3://${BOOTSTRAP_BUCKET}/join-commands/worker-join.sh /tmp/worker-join.sh; then
    echo "[ERROR] Failed to download worker join command"
    exit 1
fi

chmod +x /tmp/worker-join.sh
echo "[SUCCESS] Worker join command downloaded"

# Display the join command (without executing yet)
echo "[INFO] Join command contents:"
cat /tmp/worker-join.sh

################################################################################
# STEP 3: Wait for API server to be reachable
################################################################################
echo "[STEP 3] Verifying API server is reachable..."

max_attempts=20
attempt=1
api_reachable=false

while [ $${attempt} -le $${max_attempts} ]; do
    echo "[WAIT] Attempt $${attempt}/$${max_attempts} - Testing API server connectivity..."
    
    if timeout 5 bash -c "echo > /dev/tcp/${LB_DNS}/6443" 2>/dev/null; then
        echo "[SUCCESS] API server is reachable at ${LB_DNS}:6443"
        api_reachable=true
        break
    fi
    
    echo "[WAIT] API server not reachable yet, waiting 15 seconds..."
    sleep 15
    attempt=$(($${attempt} + 1))
done

if [ "$${api_reachable}" = false ]; then
    echo "[WARN] API server connectivity test failed, but proceeding anyway..."
fi

################################################################################
# STEP 4: Execute join command
################################################################################
echo "[STEP 4] Joining cluster as worker node..."

if ! /tmp/worker-join.sh 2>&1 | tee /tmp/kubeadm-join-output.txt; then
    echo "[ERROR] Failed to join cluster!"
    echo "[ERROR] Join output:"
    cat /tmp/kubeadm-join-output.txt
    exit 1
fi

echo "[SUCCESS] Successfully joined cluster as worker node!"

################################################################################
# STEP 5: Verify kubelet is running
################################################################################
echo "[STEP 5] Verifying kubelet is running..."

sleep 5

if systemctl is-active --quiet kubelet; then
    echo "[SUCCESS] Kubelet is running"
    systemctl status kubelet --no-pager | head -20
else
    echo "[ERROR] Kubelet is not running!"
    systemctl status kubelet --no-pager
    journalctl -u kubelet -n 50 --no-pager
    exit 1
fi

################################################################################
# STEP 6: Create ready flag for this worker
################################################################################
echo "[STEP 6] Creating ready flag in S3..."
NODE_NAME=$(hostname)
echo "ready" | aws s3 cp - s3://${BOOTSTRAP_BUCKET}/flags/$${NODE_NAME}-ready.flag
echo "[SUCCESS] $${NODE_NAME} ready flag created"

################################################################################
# STEP 7: Optional - Download kubeconfig for verification
################################################################################
echo "[STEP 7] Downloading kubeconfig for verification (optional)..."

mkdir -p /root/.kube

if aws s3 cp s3://${BOOTSTRAP_BUCKET}/configs/admin.conf /root/.kube/config 2>/dev/null; then
    chown root:root /root/.kube/config
    export KUBECONFIG=/root/.kube/config
    echo "[SUCCESS] kubectl configured"
    
    # Try to verify node registration
    echo "[INFO] Attempting to verify node registration..."
    sleep 10
    
    if kubectl get nodes 2>/dev/null | grep -q "$(hostname)"; then
        echo "[SUCCESS] Node is registered in the cluster!"
        kubectl get nodes
    else
        echo "[WARN] Node not visible yet (may take a few moments)"
    fi
else
    echo "[WARN] Could not download kubeconfig (not critical for worker nodes)"
fi

################################################################################
# FINAL STATUS
################################################################################
echo ""
echo "=========================================="
echo "WORKER NODE INITIALIZATION SUMMARY"
echo "=========================================="
echo "Hostname: $(hostname)"
echo "Role: Worker"
echo "Timestamp: $(date)"
echo ""
echo "Kubelet status:"
systemctl status kubelet --no-pager | head -10
echo ""
echo "Network interfaces:"
ip addr show | grep "inet " | grep -v "127.0.0.1"
echo ""
echo "Disk usage:"
df -h / | tail -1
echo "=========================================="
echo ""
echo "WORKER NODE JOIN COMPLETE!"
echo "The node should appear in 'kubectl get nodes' within 1-2 minutes"
echo "=========================================="

exit 0