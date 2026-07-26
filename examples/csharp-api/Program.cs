// csharp-api — ASP.NET Core blog backend with PostgreSQL storage,
// serving the shared xore//blog frontend from wwwroot/.
//
// Same API contract as every blog example in cgnat/examples:
//   public:  GET /api/posts, GET /api/posts/{id}, GET /health(/ready)
//   admin:   POST /api/admin/login + CRUD under /api/admin/posts,
//            guarded by the X-Admin-Token header (ADMIN_PASSWORD env)

using System.Diagnostics;
using System.Text.RegularExpressions;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Npgsql;

var started = Stopwatch.StartNew();
var builder = WebApplication.CreateBuilder(args);

var secret = builder.Configuration["ADMIN_PASSWORD"] ?? "change-me-cs";

// Connection string assembled from the same env vars docker-compose sets
var conn = new NpgsqlConnectionStringBuilder
{
    Host = builder.Configuration["POSTGRES_HOST"] ?? "postgres",
    Port = int.TryParse(builder.Configuration["POSTGRES_PORT"], out var pgPort) ? pgPort : 5432,
    Database = builder.Configuration["POSTGRES_DB"] ?? "blog",
    Username = builder.Configuration["POSTGRES_USER"] ?? "blog",
    Password = builder.Configuration["POSTGRES_PASSWORD"] ?? "changeme",
}.ConnectionString;

builder.Services.AddDbContext<BlogDb>(o => o.UseNpgsql(conn));

// Per-client-IP fixed-window rate limit (Traefik also rate-limits at the edge)
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    o.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(ctx =>
        RateLimitPartition.GetFixedWindowLimiter(
            ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 100,
                Window = TimeSpan.FromSeconds(10),
            }));
});

var app = builder.Build();
app.UseRateLimiter();

// Serve the shared frontend (wwwroot/index.html, app.js, xore.css)
app.UseDefaultFiles();
app.UseStaticFiles();

// Create the schema on startup, retrying while Postgres warms up
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<BlogDb>();
    for (var attempt = 1; ; attempt++)
    {
        try
        {
            db.Database.EnsureCreated();
            if (!db.Posts.Any())
            {
                var now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
                db.Posts.Add(new Post
                {
                    Title = "Welcome to the ASP.NET Core blog",
                    Slug = "welcome-to-the-aspnet-core-blog",
                    Content = "This blog runs behind a CGNAT VPS gateway — self-hosted, no open "
                            + "ports, zero-trust.\n\nBackend: ASP.NET Core 9 minimal API, storage: "
                            + "PostgreSQL via EF Core.\n\nEdit or delete this post from the admin panel.",
                    Published = true,
                    CreatedAt = now,
                    UpdatedAt = now,
                });
                db.SaveChanges();
            }
            break;
        }
        catch (Exception ex) when (attempt < 10)
        {
            app.Logger.LogWarning("Postgres not ready (attempt {Attempt}/10): {Message}", attempt, ex.Message);
            Thread.Sleep(2000);
        }
    }
}

static string Slugify(string title) =>
    Regex.Replace(Regex.Replace(title.ToLowerInvariant(), "[^a-z0-9]+", "-"), "^-+|-+$", "");

static long NowMs() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

bool Authorized(HttpContext ctx) =>
    ctx.Request.Headers["X-Admin-Token"] == secret;

// ---- Health ----

app.MapGet("/health", async (BlogDb db) =>
{
    int count;
    try { count = await db.Posts.CountAsync(); }
    catch { count = -1; }
    return Results.Ok(new
    {
        status = "ok",
        posts = count,
        uptime_seconds = (long)started.Elapsed.TotalSeconds,
    });
});

app.MapGet("/health/ready", async (BlogDb db) =>
    await db.Database.CanConnectAsync()
        ? Results.Ok(new { status = "ready", postgres = "ok" })
        : Results.Json(new { status = "degraded", postgres = "unreachable" }, statusCode: 503));

// ---- Public API ----

app.MapPost("/api/admin/login", ([FromBody] LoginInput input) =>
    input.Password == secret
        ? Results.Ok(new { ok = true, token = secret })
        : Results.Json(new { error = "Invalid password" }, statusCode: 401));

app.MapGet("/api/posts", async (BlogDb db) =>
    Results.Ok(await db.Posts.AsNoTracking()
        .Where(p => p.Published)
        .OrderByDescending(p => p.CreatedAt)
        .ToListAsync()));

app.MapGet("/api/posts/{id:int}", async (BlogDb db, int id) =>
    await db.Posts.AsNoTracking().FirstOrDefaultAsync(p => p.Id == id && p.Published) is { } post
        ? Results.Ok(post)
        : Results.NotFound(new { error = "Not found" }));

// ---- Admin API ----

app.MapGet("/api/admin/posts", async (HttpContext ctx, BlogDb db) =>
{
    if (!Authorized(ctx)) return Results.Json(new { error = "Unauthorized" }, statusCode: 401);
    return Results.Ok(await db.Posts.AsNoTracking()
        .OrderByDescending(p => p.CreatedAt)
        .ToListAsync());
});

app.MapPost("/api/admin/posts", async (HttpContext ctx, BlogDb db, [FromBody] PostInput input) =>
{
    if (!Authorized(ctx)) return Results.Json(new { error = "Unauthorized" }, statusCode: 401);
    if (string.IsNullOrWhiteSpace(input.Title) || string.IsNullOrWhiteSpace(input.Content))
        return Results.BadRequest(new { error = "title and content required" });

    var now = NowMs();
    var post = new Post
    {
        Title = input.Title.Trim(),
        Slug = string.IsNullOrWhiteSpace(input.Slug) ? Slugify(input.Title) : input.Slug.Trim(),
        Content = input.Content,
        Published = input.Published ?? false,
        CreatedAt = now,
        UpdatedAt = now,
    };
    db.Posts.Add(post);
    await db.SaveChangesAsync();
    return Results.Created($"/api/posts/{post.Id}", post);
});

app.MapPut("/api/admin/posts/{id:int}", async (HttpContext ctx, BlogDb db, int id, [FromBody] PostInput input) =>
{
    if (!Authorized(ctx)) return Results.Json(new { error = "Unauthorized" }, statusCode: 401);
    var post = await db.Posts.FindAsync(id);
    if (post is null) return Results.NotFound(new { error = "Not found" });

    if (input.Title is not null) post.Title = input.Title.Trim();
    if (input.Slug is not null) post.Slug = input.Slug.Trim();
    if (input.Content is not null) post.Content = input.Content;
    if (input.Published is not null) post.Published = input.Published.Value;
    post.UpdatedAt = NowMs();

    await db.SaveChangesAsync();
    return Results.Ok(post);
});

app.MapDelete("/api/admin/posts/{id:int}", async (HttpContext ctx, BlogDb db, int id) =>
{
    if (!Authorized(ctx)) return Results.Json(new { error = "Unauthorized" }, statusCode: 401);
    var deleted = await db.Posts.Where(p => p.Id == id).ExecuteDeleteAsync();
    return deleted > 0
        ? Results.NoContent()
        : Results.NotFound(new { error = "Not found" });
});

app.Run();

class Post
{
    public int Id { get; set; }
    public string Title { get; set; } = "";
    public string Slug { get; set; } = "";
    public string Content { get; set; } = "";
    public bool Published { get; set; }
    public long CreatedAt { get; set; }
    public long UpdatedAt { get; set; }
}

class BlogDb(DbContextOptions<BlogDb> options) : DbContext(options)
{
    public DbSet<Post> Posts => Set<Post>();
}

record LoginInput(string? Password);
record PostInput(string? Title, string? Slug, string? Content, bool? Published);
