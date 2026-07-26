"""python-api — Flask blog backend serving the shared xore//blog frontend.

Same API contract as every blog example in cgnat/examples:
  public:  GET /api/posts, GET /api/posts/<id>, GET /health
  admin:   POST /api/admin/login + CRUD under /api/admin/posts,
           guarded by the X-Admin-Token header (ADMIN_PASSWORD env)
Storage: JSON flat file (data/posts.json) — run gunicorn with 1 worker.
"""

import json
import os
import re
import time
import uuid

from flask import Flask, jsonify, request

app = Flask(__name__, static_folder="static", static_url_path="")

SECRET = os.environ.get("ADMIN_PASSWORD", "change-me-py")
DATA = os.environ.get(
    "DATA_FILE", os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "posts.json")
)


def now_ms():
    return int(time.time() * 1000)


def slugify(title):
    return re.sub(r"^-+|-+$", "", re.sub(r"[^a-z0-9]+", "-", title.lower()))


def load():
    try:
        with open(DATA, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return []


def save(posts):
    os.makedirs(os.path.dirname(DATA), exist_ok=True)
    tmp = DATA + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(posts, f, indent=2)
    os.replace(tmp, DATA)


# Seed a welcome post on first start
if not load():
    save([{
        "id": str(uuid.uuid4()),
        "title": "Welcome to the Flask blog",
        "slug": "welcome-to-the-flask-blog",
        "content": "This blog runs behind a CGNAT VPS gateway — self-hosted, no open ports, "
                   "zero-trust.\n\nBackend: Flask + Gunicorn, storage: JSON flat file.\n\n"
                   "Edit or delete this post from the admin panel.",
        "published": True,
        "createdAt": now_ms(),
        "updatedAt": now_ms(),
    }])


def authorized():
    return request.headers.get("X-Admin-Token") == SECRET


@app.get("/")
def index():
    return app.send_static_file("index.html")


@app.get("/health")
def health():
    return jsonify(status="ok", posts=len(load()))


@app.post("/api/admin/login")
def login():
    body = request.get_json(silent=True) or {}
    if body.get("password") != SECRET:
        return jsonify(error="Invalid password"), 401
    return jsonify(ok=True, token=SECRET)


@app.get("/api/posts")
def public_posts():
    posts = [p for p in load() if p.get("published")]
    posts.sort(key=lambda p: p["createdAt"], reverse=True)
    return jsonify(posts)


@app.get("/api/posts/<post_id>")
def public_post(post_id):
    post = next((p for p in load() if p["id"] == post_id), None)
    if not post or not post.get("published"):
        return jsonify(error="Not found"), 404
    return jsonify(post)


@app.get("/api/admin/posts")
def admin_posts():
    if not authorized():
        return jsonify(error="Unauthorized"), 401
    posts = load()
    posts.sort(key=lambda p: p["createdAt"], reverse=True)
    return jsonify(posts)


@app.post("/api/admin/posts")
def admin_create():
    if not authorized():
        return jsonify(error="Unauthorized"), 401
    body = request.get_json(silent=True) or {}
    title = (body.get("title") or "").strip()
    content = body.get("content") or ""
    if not title or not content.strip():
        return jsonify(error="title and content required"), 400
    post = {
        "id": str(uuid.uuid4()),
        "title": title,
        "slug": (body.get("slug") or "").strip() or slugify(title),
        "content": content,
        "published": bool(body.get("published", False)),
        "createdAt": now_ms(),
        "updatedAt": now_ms(),
    }
    posts = load()
    posts.append(post)
    save(posts)
    return jsonify(post), 201


@app.put("/api/admin/posts/<post_id>")
def admin_update(post_id):
    if not authorized():
        return jsonify(error="Unauthorized"), 401
    body = request.get_json(silent=True) or {}
    posts = load()
    post = next((p for p in posts if p["id"] == post_id), None)
    if not post:
        return jsonify(error="Not found"), 404
    for key in ("title", "slug", "content", "published"):
        if key in body:
            post[key] = body[key]
    post["updatedAt"] = now_ms()
    save(posts)
    return jsonify(post)


@app.delete("/api/admin/posts/<post_id>")
def admin_delete(post_id):
    if not authorized():
        return jsonify(error="Unauthorized"), 401
    posts = load()
    remaining = [p for p in posts if p["id"] != post_id]
    if len(remaining) == len(posts):
        return jsonify(error="Not found"), 404
    save(remaining)
    return "", 204


if __name__ == "__main__":
    # Development only — in production the Dockerfile runs gunicorn directly
    app.run(host="0.0.0.0", port=5000)
