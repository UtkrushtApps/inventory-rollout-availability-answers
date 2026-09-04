#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

NAMESPACE="cartforge"
DEPLOYMENT="inventory-api"
SERVICE="inventory-api"
CLIENT="inventory-hidden-observer"
DURATION="45"

cleanup() {
  kubectl delete pod "$CLIENT" -n "$NAMESPACE" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

diagnostics() {
  echo "=== Deployment ==="
  kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o wide || true
  echo "=== Pods ==="
  kubectl get pods -n "$NAMESPACE" -o wide || true
  echo "=== EndpointSlices ==="
  kubectl get endpointslices -n "$NAMESPACE" -l kubernetes.io/service-name="$SERVICE" -o yaml || true
  echo "=== Events ==="
  kubectl get events -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp | tail -n 30 || true
  echo "=== Logs ==="
  kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/name=inventory-api --all-containers=true --tail=50 --prefix=true || true
}

fail() {
  echo "FAILED: $1" >&2
  diagnostics
  exit 1
}

trap cleanup EXIT

command -v minikube >/dev/null 2>&1 || fail "minikube is unavailable"
command -v kubectl >/dev/null 2>&1 || fail "kubectl is unavailable"
kubectl get --raw=/readyz >/dev/null 2>&1 || fail "Kubernetes API is unavailable"

cleanup

echo "Building the submitted application image..."
minikube image build -t inventory-api:local . >/dev/null

kubectl delete namespace "$NAMESPACE" --ignore-not-found --wait=true >/dev/null
./scripts/apply.sh >/dev/null

if ! kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=90s; then
  fail "initial Deployment did not reach its desired state"
fi

desired="$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')"
ready="$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')"
[[ -n "$desired" && "$desired" -gt 0 ]] || fail "Deployment has no desired replicas"
[[ "$ready" == "$desired" ]] || fail "Deployment is not fully ready"

addresses="$(kubectl get endpointslices -n "$NAMESPACE" -l kubernetes.io/service-name="$SERVICE" -o jsonpath='{range .items[*].endpoints[*].addresses[*]}{.}{"\n"}{end}')"
[[ -n "$addresses" ]] || fail "Service has no EndpointSlice addresses"

kubectl run "$CLIENT" \
  -n "$NAMESPACE" \
  --image=inventory-api:local \
  --image-pull-policy=Never \
  --restart=Never \
  --env="DURATION=$DURATION" \
  --command -- python -c '
import json
import os
import time
import urllib.request

url = "http://inventory-api:8000/api/v1/stock/CF-HIDDEN-99"
deadline = time.monotonic() + float(os.environ["DURATION"])
failures = []
successes = 0
while time.monotonic() < deadline:
    started = time.monotonic()
    try:
        with urllib.request.urlopen(url, timeout=1.0) as response:
            raw = response.read()
            body = json.loads(raw)
            valid = (
                response.status == 200
                and body.get("sku") == "CF-HIDDEN-99"
                and body.get("available") is True
                and isinstance(body.get("quantity"), int)
                and body.get("quantity", 0) > 0
                and body.get("warehouse") == "north-america-primary"
                and isinstance(body.get("checked_at"), str)
            )
            if valid:
                successes += 1
            else:
                failures.append({"type": "contract", "status": response.status})
    except Exception as exc:
        failures.append({"type": type(exc).__name__, "detail": str(exc)[:160]})
    elapsed = time.monotonic() - started
    if elapsed > 1.0:
        failures.append({"type": "budget", "elapsed": round(elapsed, 3)})
    time.sleep(0.04)
print(json.dumps({"successes": successes, "failure_count": len(failures), "failures": failures[:12]}), flush=True)
raise SystemExit(1 if failures or successes == 0 else 0)
' >/dev/null

for attempt in $(seq 1 20); do
  phase="$(kubectl get pod "$CLIENT" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "$phase" == "Running" ]] && break
  [[ "$phase" == "Failed" || "$phase" == "Succeeded" ]] && break
  sleep 1
done

[[ "$(kubectl get pod "$CLIENT" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)" == "Running" ]] || fail "request observer did not start"

kubectl rollout restart deployment/"$DEPLOYMENT" -n "$NAMESPACE" >/dev/null
if ! kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=40s; then
  fail "rolling restart did not converge within its deadline"
fi

for attempt in $(seq 1 60); do
  phase="$(kubectl get pod "$CLIENT" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]] && break
  sleep 1
done

observer_phase="$(kubectl get pod "$CLIENT" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
observer_log="$(kubectl logs "$CLIENT" -n "$NAMESPACE" 2>&1 || true)"
echo "$observer_log"
[[ "$observer_phase" == "Succeeded" ]] || fail "continuous Service observation reported a failure"

desired="$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')"
ready="$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')"
available="$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.availableReplicas}')"
[[ "$ready" == "$desired" && "$available" == "$desired" ]] || fail "Deployment did not return to full availability"

ready_addresses="$(kubectl get endpointslices -n "$NAMESPACE" -l kubernetes.io/service-name="$SERVICE" -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)].addresses[*]}{.}{"\n"}{end}')"
[[ -n "$ready_addresses" ]] || fail "Service has no ready backends after restart"

restart_total="$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=inventory-api -o jsonpath='{range .items[*].status.containerStatuses[*]}{.restartCount}{"\n"}{end}' | awk '{sum += $1} END {print sum + 0}')"
[[ "$restart_total" -le 2 ]] || fail "container restarts exceeded the accepted bound"

echo "PASS: rollout converged with full availability and no observed Service failure."
