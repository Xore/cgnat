# Multi-stage build: SDK to compile, slim ASP.NET runtime to serve
FROM mcr.microsoft.com/dotnet/sdk:9.0-alpine AS build
WORKDIR /src

# Restore first so the NuGet layer is cached between code changes
COPY BlogApi.csproj .
RUN dotnet restore

COPY . .
RUN dotnet publish -c Release -o /app /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:9.0-alpine
WORKDIR /app
COPY --from=build /app .

ENV ASPNETCORE_URLS=http://+:5002
EXPOSE 5002

# Non-root user shipped with the .NET 8+ images
USER app

ENTRYPOINT ["dotnet", "BlogApi.dll"]
