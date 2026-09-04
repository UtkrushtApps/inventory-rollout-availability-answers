#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

NAMESPACE="cartforge"
CLIENT="inventory-rollout-observer"
DURATION="42"

cleanup() {
  kubectl delete pod "$CLIENT" -n "$NAMESPACE" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! kubectl get deployment inventory-api -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "The inventory workload is not deployed." >&2
  exit 1
fi

if ! kubectl rollout status deployment/inventory-api -n "$NAMESPACE" --timeout=60s; then
  echo "The inventory workload did not reach a ready steady state." >&2
  exit 1
fi

kubectl delete pod "$CLIENT" -n "$NAMESPACE" --ignore-not-found --wait=true >/dev/null 2>&1 || true

echo "Starting continuous inventory requests through the Service..."
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

url = "http://inventory-api:8000/api/v1/stock/CF-ROLL-42"
deadline = time.monotonic() + float(os.environ["DURATION"])
failures = []
successes = 0
while time.monotonic() < deadline:
    try:
        with urllib.request.urlopen(url, timeout=1.0) as response:
            body = json.loads(response.read())
            valid = (
                response.status == 200
                and body.get("sku") == "CF-ROLL-42"
                and body.get("available") is True
                and isinstance(body.get("quantity"), int)
                and bool(body.get("warehouse"))
            )
            if not valid:
                failures.append({"kind": "contract", "status": response.status})
            else:
                successes += 1
    except Exception as exc:
        failures.append({"kind": type(exc).__name__, "detail": str(exc)[:120]})
    time.sleep(0.05)
print(json.dumps({"successes": successes, "failures": len(failures), "samples": failures[:8]}), flush=True)
raise SystemExit(1 if failures or successes == 0 else 0)
' >/dev/null

for attempt in $(seq 1 15); do
  phase="$(kubectl get pod "$CLIENT" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [[ "$phase" == "Running" ]]; then
    break
  fi
  if [[ "$phase" == "Failed" || "$phase" == "Succeeded" ]]; then
    break
  fi
  sleep 1
done

echo "Restarting the inventory workload while observations continue..."
kubectl rollout restart deployment/inventory-api -n "$NAMESPACE" >/dev/null
kubectl rollout status deployment/inventory-api -n "$NAMESPACE" --timeout=35s
rollout_rc=$?

for attempt in $(seq 1 55); do
  phase="$(kubectl get pod "$CLIENT" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]]; then
    break
  fi
  sleep 1
done

result="$(kubectl logs "$CLIENT" -n "$NAMESPACE" 2>&1 || true)"
echo "$result"
phase="$(kubectl get pod "$CLIENT" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)"

if [[ "$rollout_rc" -ne 0 ]]; then
  echo "Reproduction failed: rollout did not converge within the observation window." >&2
  ./scripts/status.sh || true
  exit 1
fi

if [[ "$phase" != "Succeeded" ]]; then
  echo "Reproduction failed: one or more Service requests were unsuccessful." >&2
  ./scripts/status.sh || true
  exit 1
fi

if ! grep -q '"failures": 0' <<<"$result"; then
  echo "Reproduction failed: the request observer reported failures." >&2
  exit 1
fi

echo "Reproduction passed: rollout converged without an observed request failure."
