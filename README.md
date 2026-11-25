# WeatherApi: Kubernetes Modernization

Small ASP.NET Core Web API used as the target application for the CA2 Kanban project
(Jira space `KAN`). The goal was to take an application that only ran on a developer
machine and make it run on Kubernetes in a standardized, reproducible way.

The application is the official ASP.NET Core Web API template (`dotnet new webapi`, .NET 10),
extended with configuration from the environment and health endpoints.

| Endpoint | Purpose |
|---|---|
| `GET /weatherforecast` | Sample data; number of days comes from `Forecast:Days` |
| `GET /info` | Active configuration (environment, forecast days, whether the API key is set; never the key itself) |
| `GET /health/live` | Liveness probe: the process is up |
| `GET /health/ready` | Readiness probe: the app can receive traffic |

## Architecture

```
GitHub push (main)
   └─> GitHub Actions: build multi-arch image (amd64 + arm64) ──> ghcr.io/luiscloud3591/weather-api-k8s:<commit-sha>
                                                                         │
minikube cluster                                                         ▼
   Ingress (weather-api.local) ──> Service (ClusterIP :80) ──> Deployment (2–5 pods, :8080)
                                                                 ├─ ConfigMap  (Forecast__Days, App__EnvironmentName)
                                                                 ├─ Secret     (Api__Key, created with kubectl, not in Git)
                                                                 ├─ liveness / readiness probes
                                                                 └─ HorizontalPodAutoscaler (50% CPU of a 100m request)
```

## Repository structure

| Path | Content |
|---|---|
| `Program.cs`, `WeatherApi.csproj` | The API |
| `Dockerfile` | Multi-stage build (sdk:10.0 → aspnet:10.0), non-root user, port 8080 |
| `.github/workflows/build-and-push.yml` | CI: build and push the image to GHCR on every push to `main` |
| `k8s/` | Kubernetes manifests applied with `kubectl apply -f k8s/` |
| `k8s/templates/secret.example.yaml` | Example of the Secret (the real one is never committed) |
| `loadtest/` | Load generator and script used to validate the autoscaler |

## Scope

**In scope:** container image, CI pipeline, deployment to a local minikube cluster, ConfigMap and Secret,
health probes, Ingress, resource requests/limits, autoscaling validated with a load test, this documentation.

**Out of scope:** changing the business logic, cloud/production clusters (EKS, AKS, GKE), TLS certificates,
authentication, databases, monitoring stack (Prometheus/Grafana) and GitOps (Argo CD). See *Future improvements*.

## Prerequisites

- Docker Desktop (running)
- minikube and kubectl (`brew install minikube kubectl`)
- .NET SDK 10 (only to run or build the app outside Kubernetes)

> **Check your kubectl context first.** If you also work with other clusters, make sure every command
> targets minikube. All commands below pass `--context minikube` explicitly for this reason.

## 1. Run locally (optional)

```bash
dotnet run --launch-profile http
curl http://localhost:5111/weatherforecast
```

Or as a container:

```bash
docker build -t weather-api:local .
docker run --rm -p 8080:8080 weather-api:local
curl http://localhost:8080/weatherforecast
```

## 2. Build and publish the image (CI)

Every push to `main` runs `.github/workflows/build-and-push.yml`, which pushes
`ghcr.io/luiscloud3591/weather-api-k8s:<commit-sha>` and `:latest` for `linux/amd64` and `linux/arm64`.
Changes only to `k8s/`, `loadtest/` or Markdown files do not trigger a build.

The Deployment uses an image pinned to a commit SHA (not `:latest`). To roll out a new version,
update the `image:` line in `k8s/deployment.yaml` to the new SHA.

## 3. Deploy to minikube

```bash
# Start the cluster and enable the add-ons used by the Ingress and the autoscaler
minikube start --driver=docker --cpus=4 --memory=4096
minikube addons enable ingress
minikube addons enable metrics-server

# Wait for the ingress controller: its admission webhook must be up before an Ingress can be created
kubectl --context minikube -n ingress-nginx wait --for=condition=ready pod \
  -l app.kubernetes.io/component=controller --timeout=180s

# Create the namespace first
kubectl --context minikube apply -f k8s/00-namespace.yaml

# Create the Secret BEFORE the Deployment (otherwise the pods fail with CreateContainerConfigError)
kubectl --context minikube -n weather-api create secret generic weather-api-secret \
  --from-literal=Api__Key="$(openssl rand -hex 16)"

# Apply all manifests and wait for the rollout
kubectl --context minikube apply -f k8s/
kubectl --context minikube -n weather-api rollout status deploy/weather-api
```

## 4. Test

```bash
kubectl --context minikube -n weather-api get pods,svc,ingress,hpa
```

**Through the Service** (works on any OS):

```bash
kubectl --context minikube -n weather-api port-forward svc/weather-api 8090:80
curl http://localhost:8090/info
curl http://localhost:8090/health/ready
```

**Through the Ingress (hostname `weather-api.local`).** On macOS with the Docker driver the minikube IP
is not reachable from the host, so a tunnel is needed:

```bash
minikube tunnel                                            # keep running; asks for the admin password
echo "127.0.0.1 weather-api.local" | sudo tee -a /etc/hosts  # once
curl http://weather-api.local/info
```

## 5. Configuration

| Setting | Source | Key (environment variable) |
|---|---|---|
| Forecast days | ConfigMap `weather-api-config` | `Forecast__Days` |
| Environment name | ConfigMap `weather-api-config` | `App__EnvironmentName` |
| API key | Secret `weather-api-secret` | `Api__Key` |

Configuration is read at start-up, so restart the pods after changing the ConfigMap:

```bash
kubectl --context minikube -n weather-api edit configmap weather-api-config
kubectl --context minikube -n weather-api rollout restart deploy/weather-api
```

## 6. Autoscaling and load test

The HorizontalPodAutoscaler keeps 2–5 replicas and targets 50% of the 100m CPU request.
The Deployment intentionally has no `replicas` field: the autoscaler owns the replica count.

```bash
./loadtest/run-and-record.sh hpa-timeline.txt   # ~11 minutes: load, then cooldown
# or manually:
kubectl --context minikube -n weather-api apply -f loadtest/load-generator.yaml
kubectl --context minikube -n weather-api get hpa -w
kubectl --context minikube -n weather-api delete -f loadtest/load-generator.yaml
```

Observed result (25/11/2026): CPU reached 118% of the target and the autoscaler scaled 2 → 4 → 5 replicas
in about 30 seconds. After the load stopped, replicas returned to 2 after about 6 minutes
(default 5-minute scale-down stabilization).

## 7. Troubleshooting (lessons learned during the project)

| Symptom | Cause | Fix |
|---|---|---|
| `failed calling webhook "validate.nginx.ingress.kubernetes.io"` when applying `k8s/` | Ingress controller enabled but not ready yet (fresh cluster) | Wait for the controller pod (step 3), then `kubectl apply -f k8s/` again |
| Pod in `CreateContainerConfigError` | Secret `weather-api-secret` does not exist | Create the Secret, then the rollout continues |
| `kubectl get hpa` shows `<unknown>` | metrics-server has no data yet (about 1–2 minutes after `minikube start` or after enabling the add-on) or is not enabled | Wait, or `minikube addons enable metrics-server` |
| `curl http://$(minikube ip)` times out on macOS | Docker driver does not expose the minikube IP to the host | Use `port-forward` or `minikube tunnel` |
| Replica count jumps back to a fixed number after `kubectl apply` | `replicas` set in the Deployment fights the autoscaler | Keep `replicas` out of the Deployment |
| Commands hit the wrong cluster | Current kubectl context is another cluster | Always use `--context minikube` (or `kubectx minikube`) |

## 8. Clean up

```bash
kubectl --context minikube delete namespace weather-api   # remove the application
minikube stop                                              # stop the cluster (keeps it)
minikube delete                                            # remove the cluster completely
```

## Future improvements

- Convert the original Hangman console game into a Web API and deploy it the same way
- GitOps with Argo CD (the cluster pulls changes from Git)
- Monitoring with Prometheus and Grafana
- TLS on the Ingress
- Update the GitHub Actions versions (Node.js 20 deprecation warning)
