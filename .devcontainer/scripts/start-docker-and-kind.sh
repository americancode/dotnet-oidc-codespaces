#!/usr/bin/env bash
set -euo pipefail

echo "Waiting for Docker daemon..."
max_wait=120
while ! docker info >/dev/null 2>&1; do
  if [ $max_wait -le 0 ]; then
    echo "Timed out waiting for Docker" >&2
    exit 1
  fi
  sleep 1
  max_wait=$((max_wait - 1))
done

CLUSTER_NAME="codespaces"
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Kind cluster '${CLUSTER_NAME}' already exists."
else
  echo "Creating kind cluster '${CLUSTER_NAME}'..."
  kind create cluster --name "${CLUSTER_NAME}"
fi

echo "Setting kubectl context to kind-${CLUSTER_NAME}"
kubectl cluster-info --context "kind-${CLUSTER_NAME}" || true

echo "kind is ready"
