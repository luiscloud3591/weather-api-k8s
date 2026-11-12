# WeatherApi: Kubernetes Modernization

Small ASP.NET Core Web API used as the target application for the CA2 Kanban project
(Jira space `KAN`). The goal is to take an application that only runs on a developer
machine and make it run on Kubernetes in a standardized, reproducible way.

The application is the official ASP.NET Core Web API template
(`dotnet new webapi`, .NET 10), which exposes a `GET /weatherforecast` endpoint
returning random sample data.

## Scope

### In scope
- Containerize the application (Dockerfile)
- CI pipeline (GitHub Actions) that builds and pushes the image to GitHub Container Registry
- Deploy to a local Kubernetes cluster (minikube) with Deployment and Service
- Externalized configuration (ConfigMap and Secret)
- Health checks (liveness and readiness probes)
- Ingress to expose the API by hostname
- Resource requests/limits and Horizontal Pod Autoscaler, validated with a load test
- Deployment documentation

### Out of scope
- Changing the business logic of the API
- Cloud/production cluster (EKS, AKS, GKE), only local minikube
- TLS certificates, authentication and databases
- Monitoring stack (Prometheus/Grafana) and GitOps (Argo CD): possible future improvements

## Run locally (before any change)

Prerequisite: .NET SDK 10.

```bash
dotnet run --launch-profile http
curl http://localhost:5111/weatherforecast
```
