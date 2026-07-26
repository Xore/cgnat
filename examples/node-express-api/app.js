/* =========================================================
   node-express-api — Express blog backend
   Serves the shared xore//blog frontend from public/ + the REST API.
   Same API contract as every blog example in cgnat/examples.
   Storage: JSON flat file (data/posts.json).
   Admin auth: X-Admin-Token header (ADMIN_PASSWORD env).
   ========================================================= */
"use strict";

const express = require("express");
const fs      = require("fs");
const path    = require("path");
const crypto  = require("crypto");

const app    = express();
const PORT   = process.env.PORT || 3000;
const SECRET = process.env.ADMIN_PASSWORD || "change-me-js";
const DATA   = process.env.DATA_FILE || path.join(__dirname, "data", "posts.json");

app.use(express.json());

fs.mkdirSync(path.dirname(DATA), { recursive: true });
let posts = [];
const load = () => {
  try { posts = JSON.parse(fs.readFileSync(DATA, "utf8")); }
  catch { posts = []; }
};
const save = () => fs.writeFileSync(DATA, JSON.stringify(posts, null, 2));
load();

if (posts.length === 0) {
  posts.push({
    id: crypto.randomUUID(),
    title: "Welcome to the Express blog",
    slug: "welcome-to-the-express-blog",
    content: "This blog runs behind a CGNAT VPS gateway — self-hosted, no open ports, zero-trust.\n\nBackend: Node.js + Express, storage: JSON flat file.\n\nEdit or delete this post from the admin panel.",
    published: true,
    createdAt: Date.now(),
    updatedAt: Date.now()
  });
  save();
}

const guard = (req, res, next) => {
  if (req.headers["x-admin-token"] !== SECRET)
    return res.status(401).json({ error: "Unauthorized" });
  next();
};

app.get("/health", (_req, res) =>
  res.json({ status: "ok", posts: posts.length })
);

app.post("/api/admin/login", (req, res) => {
  const { password } = req.body || {};
  if (!password || password !== SECRET) {
    return res.status(401).json({ error: "Invalid password" });
  }
  return res.json({ ok: true, token: SECRET });
});

app.get("/api/posts", (_req, res) => {
  res.json(
    posts
      .filter(p => p.published)
      .sort((a, b) => b.createdAt - a.createdAt)
  );
});

app.get("/api/posts/:id", (req, res) => {
  const p = posts.find(p => p.id === req.params.id);
  if (!p || !p.published) return res.status(404).json({ error: "Not found" });
  res.json(p);
});

app.get("/api/admin/posts", guard, (_req, res) => {
  res.json([...posts].sort((a, b) => b.createdAt - a.createdAt));
});

app.post("/api/admin/posts", guard, (req, res) => {
  const { title, slug, content, published = false } = req.body || {};
  if (!title || !content)
    return res.status(400).json({ error: "title and content required" });
  const post = {
    id: crypto.randomUUID(),
    title,
    slug: slug || title.toLowerCase().replace(/[^a-z0-9]+/g, "-"),
    content, published,
    createdAt: Date.now(),
    updatedAt: Date.now()
  };
  posts.push(post);
  save();
  res.status(201).json(post);
});

app.put("/api/admin/posts/:id", guard, (req, res) => {
  const idx = posts.findIndex(p => p.id === req.params.id);
  if (idx === -1) return res.status(404).json({ error: "Not found" });
  posts[idx] = { ...posts[idx], ...req.body, id: posts[idx].id, updatedAt: Date.now() };
  save();
  res.json(posts[idx]);
});

app.delete("/api/admin/posts/:id", guard, (req, res) => {
  const idx = posts.findIndex(p => p.id === req.params.id);
  if (idx === -1) return res.status(404).json({ error: "Not found" });
  posts.splice(idx, 1);
  save();
  res.sendStatus(204);
});

// The frontend is a hash-routed SPA — plain static serving is enough.
app.use(express.static(path.join(__dirname, "public")));

app.listen(PORT, "0.0.0.0", () =>
  console.log(`[node-blog] listening on :${PORT}`)
);
