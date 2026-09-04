#!/usr/bin/env bash
set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Starting Kubernetes/minikube cleanup..."
if command -v minikube >/dev/null 2>&1; then
  echo "Current minikube status:"
  minikube status || true

  echo "Deleting all minikube profiles and cached state..."
  minikube delete --all --purge || true
else
  echo "minikube is not installed; continuing idempotent cleanup."
fi

echo "Removing task-generated local artifacts..."
rm -rf tmp logs .task-results || true
rm -f ./*.log ./*.out || true

echo "Pruning optional Docker remnants..."
if command -v docker >/dev/null 2>&1; then
  docker container prune -f || true
  docker network prune -f || true
  docker volume prune -f || true
fi

echo "Cleanup completed successfully!"
exit 0
