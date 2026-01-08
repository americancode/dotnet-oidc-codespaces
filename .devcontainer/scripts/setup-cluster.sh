#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="devcontainer"

echo "=== Waiting for Docker daemon ==="
max_wait=120
while ! docker info >/dev/null 2>&1; do
  if [ $max_wait -le 0 ]; then
    echo "Timed out waiting for Docker" >&2
    exit 1
  fi
  sleep 1
  max_wait=$((max_wait - 1))
done
echo "Docker is ready"

echo "=== Creating kind cluster ==="
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "Kind cluster '${CLUSTER_NAME}' already exists"
else
  cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
fi

echo "=== Waiting for cluster to be ready ==="
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo "=== Installing Gateway API CRDs ==="
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

echo "=== Adding Helm repos ==="
helm repo add traefik https://traefik.github.io/charts
helm repo add jetstack https://charts.jetstack.io
helm repo update

echo "=== Installing cert-manager ==="
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait

echo "=== Installing Traefik with Gateway API support ==="
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --set providers.kubernetesGateway.enabled=true \
  --set gateway.enabled=true \
  --set gateway.listeners.web.port=8000 \
  --set gateway.listeners.web.protocol=HTTP \
  --set gateway.listeners.websecure.port=8443 \
  --set gateway.listeners.websecure.protocol=HTTPS \
  --set service.type=NodePort \
  --set ports.web.nodePort=80 \
  --set ports.websecure.nodePort=443 \
  --wait

echo "=== Cluster setup complete ==="
echo ""
echo "Tools available:"
echo "  - kubectl (context: kind-${CLUSTER_NAME})"
echo "  - Traefik with Gateway API (namespace: traefik)"
echo "  - cert-manager (namespace: cert-manager)"
echo ""
kubectl get nodes
