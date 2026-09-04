#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "[run] installing Python dependencies..."
pip install -q -r requirements.txt

for required in Dockerfile requirements.txt manifests/namespace.yaml scripts/apply.sh; do
  if [[ ! -f "$required" ]]; then
    echo "Required repository file is missing: $required" >&2
    exit 1
  fi
done

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but was not found." >&2
  exit 1
fi

if ! command -v minikube >/dev/null 2>&1; then
  echo "Installing minikube..."
  curl -fsSL https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
    -o /usr/local/bin/minikube
  chmod +x /usr/local/bin/minikube
fi

echo "Starting the pinned minikube cluster..."
minikube start \
  --driver=docker \
  --force \
  --cpus=2 \
  --memory=1800mb \
  --kubernetes-version=v1.31.14 \
  --wait=apiserver

echo "Waiting for Kubernetes API and node visibility..."
for attempt in $(seq 1 30); do
  if kubectl get --raw=/readyz >/dev/null 2>&1 \
    && kubectl get nodes -o name 2>/dev/null | grep -q '^node/'; then
    break
  fi

  if [[ "$attempt" -eq 30 ]]; then
    echo "The Kubernetes API or control-plane node did not become available." >&2
    exit 1
  fi
  sleep 1
done

kubectl get nodes

echo "Building inventory-api:local inside minikube..."
minikube image build -t inventory-api:local .

echo "Applying the inventory workload..."
bash scripts/apply.sh

echo "Waiting for the initial rollout to complete..."
kubectl rollout status deployment/inventory-api -n cartforge --timeout=60s

echo "Environment bootstrapped. Inspect live status or run the reproduction check."
