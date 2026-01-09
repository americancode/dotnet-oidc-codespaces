#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="devcontainer"
HELM_TIMEOUT="${HELM_TIMEOUT:-10m}"

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

echo "=== Adding Helm repos ==="
helm repo add traefik https://traefik.github.io/charts
helm repo add jetstack https://charts.jetstack.io
helm repo update

echo "=== Installing cert-manager ==="
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait \
  --timeout "${HELM_TIMEOUT}"

echo "=== Installing Traefik (Ingress + Gateway API) ==="
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --set providers.kubernetesIngress.enabled=true \
  --set providers.kubernetesGateway.enabled=true \
  --set gateway.enabled=false \
  --set ports.web.hostPort=80 \
  --set ports.websecure.hostPort=443 \
  --wait \
  --timeout "${HELM_TIMEOUT}"

echo "=== Creating Gateway resource ==="
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: traefik-gateway
  namespace: traefik
spec:
  gatewayClassName: traefik
  listeners:
  - name: web
    port: 8000
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
  - name: websecure
    port: 8443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
      - name: wildcard-tls
        kind: Secret
    allowedRoutes:
      namespaces:
        from: All
EOF

echo "=== Deploying whoami test app ==="
kubectl create ns demo
kubectl apply -n demo -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: whoami
spec:
  selector:
    app: whoami
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
spec:
  replicas: 1
  selector:
    matchLabels:
      app: whoami
  template:
    metadata:
      labels:
        app: whoami
    spec:
      containers:
      - name: whoami
        image: traefik/whoami
        ports:
        - containerPort: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: whoami
spec:
  parentRefs:
  - name: traefik-gateway
    namespace: traefik
  hostnames:
  - "whoami.localhost"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: whoami
      port: 80
EOF

kubectl wait -n demo --for=condition=Ready pod -l app=whoami --timeout=60s

echo "=== Cluster setup complete ==="
echo ""
echo "Available:"
echo "  - kubectl (context: kind-${CLUSTER_NAME})"
echo "  - Traefik IngressClass: traefik"
echo "  - Traefik GatewayClass: traefik"
echo "  - Traefik Gateway: traefik-gateway (namespace: traefik)"
echo "  - cert-manager (namespace: cert-manager)"
echo "  - HTTP:  localhost:80"
echo "  - HTTPS: localhost:443"
echo ""
echo "Test with: curl -H 'Host: whoami.localhost' http://localhost"
echo ""
kubectl get nodes
kubectl get ingressclass,gatewayclass,gateway,httproute -A
