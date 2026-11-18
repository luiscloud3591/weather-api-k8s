var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddOpenApi();

// KAN-10: health checks used by the Kubernetes liveness and readiness probes
builder.Services.AddHealthChecks();

var app = builder.Build();

// Liveness: the process is up and able to answer (runs no dependency checks).
app.MapHealthChecks("/health/live", new Microsoft.AspNetCore.Diagnostics.HealthChecks.HealthCheckOptions
{
    Predicate = _ => false
});

// Readiness: the app is ready to receive traffic (runs all registered checks).
app.MapHealthChecks("/health/ready");

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

// HTTPS redirection removed: inside Kubernetes the container serves plain HTTP
// and TLS is terminated at the Ingress (see KAN-11).

var summaries = new[]
{
    "Freezing", "Bracing", "Chilly", "Cool", "Mild", "Warm", "Balmy", "Hot", "Sweltering", "Scorching"
};

// KAN-9: configuration comes from the environment (ConfigMap / Secret in Kubernetes).
// Environment variables use "__" as separator, e.g. Forecast__Days -> Forecast:Days.
var forecastDays = app.Configuration.GetValue("Forecast:Days", 5);
var environmentName = app.Configuration.GetValue("App:EnvironmentName", "local");
var apiKeyConfigured = !string.IsNullOrEmpty(app.Configuration["Api:Key"]);

// Shows which configuration the pod is running with. The secret value itself is never returned.
app.MapGet("/info", () => new
{
    environment = environmentName,
    forecastDays,
    apiKeyConfigured
})
.WithName("GetInfo");

app.MapGet("/weatherforecast", () =>
{
    var forecast =  Enumerable.Range(1, forecastDays).Select(index =>
        new WeatherForecast
        (
            DateOnly.FromDateTime(DateTime.Now.AddDays(index)),
            Random.Shared.Next(-20, 55),
            summaries[Random.Shared.Next(summaries.Length)]
        ))
        .ToArray();
    return forecast;
})
.WithName("GetWeatherForecast");

app.Run();

record WeatherForecast(DateOnly Date, int TemperatureC, string? Summary)
{
    public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);
}
