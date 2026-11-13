# ---- Build stage: SDK image compiles and publishes the app ----
# Runs on the builder's native platform and cross-compiles for the target
# architecture (amd64 or arm64), so multi-arch builds need no CPU emulation.
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG TARGETARCH
WORKDIR /src

# Restore first (cached layer while the .csproj does not change)
COPY WeatherApi.csproj .
RUN dotnet restore -a $TARGETARCH

COPY . .
RUN dotnet publish -c Release -a $TARGETARCH -o /app/publish --no-restore

# ---- Runtime stage: smaller ASP.NET runtime image, no SDK ----
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .

# The .NET image listens on port 8080 by default (ASPNETCORE_HTTP_PORTS=8080)
EXPOSE 8080

# Run as the non-root user that ships with the .NET images
USER $APP_UID

ENTRYPOINT ["dotnet", "WeatherApi.dll"]
