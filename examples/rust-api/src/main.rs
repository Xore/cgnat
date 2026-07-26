//! rust-api — Axum blog backend serving the shared xore//blog frontend.
//!
//! Same API contract as every blog example in cgnat/examples:
//!   public:  GET /api/posts, GET /api/posts/{id}, GET /health
//!   admin:   POST /api/admin/login + CRUD under /api/admin/posts,
//!            guarded by the X-Admin-Token header (ADMIN_PASSWORD env)
//!
//! The frontend (index.html, app.js, xore.css) is embedded into the binary
//! with include_str!. Posts persist to a JSON file (DATA_FILE, atomic save).

use std::path::PathBuf;
use std::sync::{Arc, RwLock};
use std::time::{SystemTime, UNIX_EPOCH};

use axum::extract::{Path, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{Html, IntoResponse, Json, Response};
use axum::routing::get;
use axum::Router;
use serde::{Deserialize, Serialize};
use serde_json::json;

const INDEX_HTML: &str = include_str!("../static/index.html");
const APP_JS: &str = include_str!("../static/app.js");
const XORE_CSS: &str = include_str!("../static/xore.css");

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Post {
    id: String,
    title: String,
    slug: String,
    content: String,
    published: bool,
    created_at: u64,
    updated_at: u64,
}

#[derive(Deserialize)]
struct PostInput {
    title: Option<String>,
    slug: Option<String>,
    content: Option<String>,
    published: Option<bool>,
}

#[derive(Deserialize)]
struct LoginInput {
    password: Option<String>,
}

struct AppState {
    posts: RwLock<Vec<Post>>,
    secret: String,
    data_file: PathBuf,
}

type SharedState = Arc<AppState>;

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn new_id() -> String {
    // millis + a random suffix — unique enough for a single-instance blog
    format!("{:x}-{:x}", now_ms(), rand_u64())
}

fn rand_u64() -> u64 {
    // Seeded from OS entropy via RandomState — avoids pulling in a crate
    use std::hash::{BuildHasher, Hasher};
    std::collections::hash_map::RandomState::new()
        .build_hasher()
        .finish()
}

fn slugify(title: &str) -> String {
    let mut out = String::with_capacity(title.len());
    let mut dash = true;
    for c in title.to_lowercase().chars() {
        if c.is_ascii_alphanumeric() {
            out.push(c);
            dash = false;
        } else if !dash {
            out.push('-');
            dash = true;
        }
    }
    out.trim_matches('-').to_string()
}

fn load_posts(file: &PathBuf) -> Vec<Post> {
    std::fs::read_to_string(file)
        .ok()
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default()
}

/// Atomic save: write to a temp file, then rename over the target.
fn save_posts(file: &PathBuf, posts: &[Post]) {
    if let Some(dir) = file.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let tmp = file.with_extension("json.tmp");
    if let Ok(data) = serde_json::to_string_pretty(posts) {
        if std::fs::write(&tmp, data).is_ok() {
            let _ = std::fs::rename(&tmp, file);
        }
    }
}

fn authorized(state: &AppState, headers: &HeaderMap) -> bool {
    headers
        .get("x-admin-token")
        .and_then(|v| v.to_str().ok())
        .map(|v| v == state.secret)
        .unwrap_or(false)
}

fn unauthorized() -> Response {
    (StatusCode::UNAUTHORIZED, Json(json!({ "error": "Unauthorized" }))).into_response()
}

fn not_found() -> Response {
    (StatusCode::NOT_FOUND, Json(json!({ "error": "Not found" }))).into_response()
}

/* ---------- frontend ---------- */

async fn index() -> Html<&'static str> {
    Html(INDEX_HTML)
}

async fn app_js() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "application/javascript; charset=utf-8")], APP_JS)
}

async fn xore_css() -> impl IntoResponse {
    ([(header::CONTENT_TYPE, "text/css; charset=utf-8")], XORE_CSS)
}

/* ---------- health + auth ---------- */

async fn health(State(state): State<SharedState>) -> impl IntoResponse {
    Json(json!({ "status": "ok", "posts": state.posts.read().unwrap().len() }))
}

async fn login(State(state): State<SharedState>, Json(input): Json<LoginInput>) -> Response {
    if input.password.as_deref() == Some(state.secret.as_str()) {
        Json(json!({ "ok": true, "token": state.secret })).into_response()
    } else {
        (StatusCode::UNAUTHORIZED, Json(json!({ "error": "Invalid password" }))).into_response()
    }
}

/* ---------- public API ---------- */

async fn public_posts(State(state): State<SharedState>) -> impl IntoResponse {
    let posts = state.posts.read().unwrap();
    let mut out: Vec<Post> = posts.iter().filter(|p| p.published).cloned().collect();
    out.sort_by_key(|p| std::cmp::Reverse(p.created_at));
    Json(out)
}

async fn public_post(State(state): State<SharedState>, Path(id): Path<String>) -> Response {
    let posts = state.posts.read().unwrap();
    match posts.iter().find(|p| p.id == id && p.published) {
        Some(p) => Json(p.clone()).into_response(),
        None => not_found(),
    }
}

/* ---------- admin API ---------- */

async fn admin_posts(State(state): State<SharedState>, headers: HeaderMap) -> Response {
    if !authorized(&state, &headers) {
        return unauthorized();
    }
    let posts = state.posts.read().unwrap();
    let mut out: Vec<Post> = posts.clone();
    out.sort_by_key(|p| std::cmp::Reverse(p.created_at));
    Json(out).into_response()
}

async fn admin_create(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Json(input): Json<PostInput>,
) -> Response {
    if !authorized(&state, &headers) {
        return unauthorized();
    }
    let title = input.title.unwrap_or_default().trim().to_string();
    let content = input.content.unwrap_or_default();
    if title.is_empty() || content.trim().is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({ "error": "title and content required" })),
        )
            .into_response();
    }
    let slug = match input.slug.map(|s| s.trim().to_string()) {
        Some(s) if !s.is_empty() => s,
        _ => slugify(&title),
    };
    let now = now_ms();
    let post = Post {
        id: new_id(),
        title,
        slug,
        content,
        published: input.published.unwrap_or(false),
        created_at: now,
        updated_at: now,
    };
    let mut posts = state.posts.write().unwrap();
    posts.push(post.clone());
    save_posts(&state.data_file, &posts);
    (StatusCode::CREATED, Json(post)).into_response()
}

async fn admin_update(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Path(id): Path<String>,
    Json(input): Json<PostInput>,
) -> Response {
    if !authorized(&state, &headers) {
        return unauthorized();
    }
    let mut posts = state.posts.write().unwrap();
    let Some(post) = posts.iter_mut().find(|p| p.id == id) else {
        return not_found();
    };
    if let Some(title) = input.title {
        post.title = title.trim().to_string();
    }
    if let Some(slug) = input.slug {
        post.slug = slug.trim().to_string();
    }
    if let Some(content) = input.content {
        post.content = content;
    }
    if let Some(published) = input.published {
        post.published = published;
    }
    post.updated_at = now_ms();
    let updated = post.clone();
    save_posts(&state.data_file, &posts);
    Json(updated).into_response()
}

async fn admin_delete(
    State(state): State<SharedState>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> Response {
    if !authorized(&state, &headers) {
        return unauthorized();
    }
    let mut posts = state.posts.write().unwrap();
    let before = posts.len();
    posts.retain(|p| p.id != id);
    if posts.len() == before {
        return not_found();
    }
    save_posts(&state.data_file, &posts);
    StatusCode::NO_CONTENT.into_response()
}

/* ---------- boot ---------- */

async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c().await.ok();
    };
    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("install SIGTERM handler")
            .recv()
            .await;
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
    eprintln!("shutting down");
}

#[tokio::main]
async fn main() {
    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(5004);
    let secret = std::env::var("ADMIN_PASSWORD").unwrap_or_else(|_| "change-me-rs".into());
    let data_file =
        PathBuf::from(std::env::var("DATA_FILE").unwrap_or_else(|_| "/data/posts.json".into()));

    let mut posts = load_posts(&data_file);
    if posts.is_empty() {
        let now = now_ms();
        posts.push(Post {
            id: new_id(),
            title: "Welcome to the Rust blog".into(),
            slug: "welcome-to-the-rust-blog".into(),
            content: "This blog runs behind a CGNAT VPS gateway — self-hosted, no open ports, \
                      zero-trust.\n\nBackend: Rust + Axum, storage: JSON file, frontend embedded \
                      into the binary.\n\nEdit or delete this post from the admin panel."
                .into(),
            published: true,
            created_at: now,
            updated_at: now,
        });
        save_posts(&data_file, &posts);
    }

    let state: SharedState = Arc::new(AppState {
        posts: RwLock::new(posts),
        secret,
        data_file,
    });

    let app = Router::new()
        .route("/", get(index))
        .route("/app.js", get(app_js))
        .route("/xore.css", get(xore_css))
        .route("/health", get(health))
        .route("/api/admin/login", axum::routing::post(login))
        .route("/api/posts", get(public_posts))
        .route("/api/posts/{id}", get(public_post))
        .route("/api/admin/posts", get(admin_posts).post(admin_create))
        .route(
            "/api/admin/posts/{id}",
            axum::routing::put(admin_update).delete(admin_delete),
        )
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(("0.0.0.0", port))
        .await
        .expect("bind port");
    eprintln!("listening on 0.0.0.0:{port}");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .expect("server error");
}
