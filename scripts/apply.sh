#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if ! kubectl get --raw=/readyz >/dev/null 2>&1; then
  echo "The Kubernetes API is not available." >&2
  exit 1
fi

echo "Applying namespace..."
kubectl apply -f manifests/namespace.yaml

echo "Applying runtime configuration and Service..."
kubectl apply -f manifests/configmap.yaml
kubectl apply -f manifests/service.yaml

echo "Applying inventory workload..."
kubectl apply -f manifests/deployment.yaml

echo "Current workload objects:"
kubectl get deployment,pods,service -n cartforge -o wide || true

echo "Current Service backends:"
kubectl get endpointslices \
  -n cartforge \
  -l kubernetes.io/service-name=inventory-api \
  -o wide || true
