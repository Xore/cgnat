"""redis-api — Flask blog backend with Redis storage, serving the shared
xore//blog frontend.

Same API contract as every blog example in cgnat/examples:
  public:  GET /api/posts, GET /api/posts/<id>, GET /health
  admin:   POST /api/admin/login + CRUD under /api/admin/posts,
           guarded by the X-Admin-Token header (ADMIN_PASSWORD env)
Storage: Redis — one JSON string per post (post:<id>), plus a sorted set
posts:index scored by createdAt for ordering. AOF/RDB persistence comes
from the redis container's volume.
"""

import json
import os
import re
import time
import uuid

import redis
from flask import Flask, jsonify, request

app = Flask(__name__, static_folder="static", static_url_path="")

SECRET = os.environ.get("ADMIN_PASSWORD", "change-me-redis")

r = redis.Redis(
    host=os.getenv("REDIS_HOST", "redis"),
    port=int(os.getenv("REDIS_PORT", 6379)),
    password=os.getenv("REDIS_PASSWORD") or None,
    decode_responses=True,
)

INDEX = "posts:index"


def now_ms():
    return int(time.time() * 1000)


def slugify(title):
    return re.sub(r"^-+|-+$", "", re.sub(r"[^a-z0-9]+", "-", title.lower()))


def key(post_id):
    return f"post:{post_id}"


def get_post(post_id):
    raw = r.get(key(post_id))
    return json.loads(raw) if raw else None


def put_post(post):
    r.set(key(post["id"]), json.dumps(post))
    r.zadd(INDEX, {post["id"]: post["createdAt"]})


def all_posts():
    ids = r.zrevrange(INDEX, 0, -1)
    posts = []
    for pid in ids:
        p = get_post(pid)
        if p:
            posts.append(p)
    return posts


def seed():
    if r.zcard(INDEX) == 0:
        put_post({
            "id": str(uuid.uuid4()),
            "title": "Welcome to the Redis blog",
            "slug": "welcome-to-the-redis-blog",
            "content": "This blog runs behind a CGNAT VPS gateway — self-hosted, no open "
                       "ports, zero-trust.\n\nBackend: Flask, storage: Redis (JSON strings + "
                       "a sorted-set index).\n\nEdit or delete this post from the admin panel.",
            "published": True,
            "createdAt": now_ms(),
            "updatedAt": now_ms(),
        })


try:
    seed()
except redis.exceptions.ConnectionError:
    pass  # redis not up yet — compose healthchecks gate startup ordering


def authorized():
    return request.headers.get("X-Admin-Token") == SECRET


@app.get("/")
def index():
    return app.send_static_file("index.html")


@app.get("/health")
def health():
    try:
        count = r.zcard(INDEX)
        return jsonify(status="ok", redis="ok", posts=count)
    except redis.exceptions.ConnectionError:
        return jsonify(status="degraded", redis="unreachable"), 503


@app.post("/api/admin/login")
def login():
    body = request.get_json(silent=True) or {}
    if body.get("password") != SECRET:
        return jsonify(error="Invalid password"), 401
    return jsonify(ok=True, token=SECRET)


@app.get("/api/posts")
def public_posts():
    return jsonify([p for p in all_posts() if p.get("published")])


@app.get("/api/posts/<post_id>")
def public_post(post_id):
    post = get_post(post_id)
    if not post or not post.get("published"):
        return jsonify(error="Not found"), 404
    return jsonify(post)


@app.get("/api/admin/posts")
def admin_posts():
    if not authorized():
        return jsonify(error="Unauthorized"), 401
    return jsonify(all_posts())


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
    put_post(post)
    return jsonify(post), 201


@app.put("/api/admin/posts/<post_id>")
def admin_update(post_id):
    if not authorized():
        return jsonify(error="Unauthorized"), 401
    post = get_post(post_id)
    if not post:
        return jsonify(error="Not found"), 404
    body = request.get_json(silent=True) or {}
    for k in ("title", "slug", "content", "published"):
        if k in body:
            post[k] = body[k]
    post["updatedAt"] = now_ms()
    put_post(post)
    return jsonify(post)


@app.delete("/api/admin/posts/<post_id>")
def admin_delete(post_id):
    if not authorized():
        return jsonify(error="Unauthorized"), 401
    if not r.exists(key(post_id)):
        return jsonify(error="Not found"), 404
    r.delete(key(post_id))
    r.zrem(INDEX, post_id)
    return "", 204


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
