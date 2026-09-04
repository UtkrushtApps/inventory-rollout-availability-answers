#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

NAMESPACE="cartforge"

echo "=== Deployments and replica sets ==="
kubectl get deployment,replicaset -n "$NAMESPACE" -o wide || true

echo "=== Pods ==="
kubectl get pods -n "$NAMESPACE" -o wide || true

echo "=== Service backends ==="
kubectl get service,endpoints,endpointslices -n "$NAMESPACE" -o wide || true

echo "=== EndpointSlice readiness conditions ==="
kubectl get endpointslices \
  -n "$NAMESPACE" \
  -l kubernetes.io/service-name=inventory-api \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{" ready="}{.conditions.ready}{" serving="}{.conditions.serving}{" terminating="}{.conditions.terminating}{"\n"}{end}' || true

echo
echo "=== Recent events ==="
kubectl get events -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp | tail -n 25 || true

echo "=== Recent application logs ==="
kubectl logs \
  -n "$NAMESPACE" \
  -l app.kubernetes.io/name=inventory-api \
  --all-containers=true \
  --tail=30 \
  --prefix=true || true
