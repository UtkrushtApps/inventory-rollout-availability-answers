# Solution Steps

1. Make application readiness represent actual inventory serviceability. Add a single `RuntimeState.ready` condition that requires both `accepting_requests` and completed warmup, and use it consistently in `/ready` and the stock route.

2. Keep liveness independent from warmup. `/live` only verifies that the process and event loop are running, while `/ready` returns 503 until warmup finishes or shutdown begins.

3. Return the documented flat `ErrorResponse` body from unavailable inventory requests instead of FastAPI's default nested `detail` structure.

4. Preserve the asynchronous warmup so the process starts normally, but prevent Kubernetes from adding the pod to ready EndpointSlices until the four-second warmup has completed.

5. Lower pod CPU requests from 700m to 100m. This allows two desired replicas plus the `maxSurge: 1` rollout replica to fit on the two-CPU minikube node; otherwise `maxUnavailable: 0` and an unschedulable surge pod deadlock the rollout.

6. Keep the rolling strategy at `maxSurge: 1` and `maxUnavailable: 0`, ensuring an old ready replica is not removed before a replacement becomes ready. Use `minReadySeconds: 1` to require brief readiness stability.

7. Add a startup probe against `/live`, a readiness probe against `/ready`, and a liveness probe against `/live`. The startup probe prevents liveness handling from interfering with startup, while readiness controls Service membership based on warmup state.

8. Add a three-second `preStop` delay. Once pod deletion starts, EndpointSlice readiness changes and routing can converge while the old HTTP process remains available for stale connections or kube-proxy rules.

9. Increase `terminationGracePeriodSeconds` to 15 seconds so the preStop delay, Uvicorn's graceful request draining, and the application's bounded three-second shutdown cleanup can all finish without SIGKILL.

10. Build and apply the solution with `./run.sh`. Confirm the initial Deployment reports two ready replicas and inspect EndpointSlice readiness with `./scripts/status.sh`.

11. Run `./scripts/reproduce.sh`. It continuously checks the stock response contract while triggering a rolling restart, then verifies that the rollout finishes within 35 seconds and that the observer recorded zero failures.

