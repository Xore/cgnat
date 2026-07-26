/* =========================================================
   svelte-blog — Express backend
   Serves REST API + the Svelte 5 SPA from /public
   ========================================================= */
"use strict";

const express = require("express");
const fs      = require("fs");
const path    = require("path");
const crypto  = require("crypto");

const app    = express();
const PORT   = process.env.PORT   || 3001;
const SECRET = process.env.ADMIN_SECRET || "change-me";
const DATA   = path.join(__dirname, "data", "posts.json");

app.use(express.json());
app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type,X-Admin-Token");
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});

fs.mkdirSync(path.dirname(DATA), { recursive: true });
let posts = [];
const load = () => { try { posts = JSON.parse(fs.readFileSync(DATA, "utf8")); } catch { posts = []; } };
const save = () => fs.writeFileSync(DATA, JSON.stringify(posts, null, 2));
load();

if (posts.length === 0) {
  posts.push({
    id: crypto.randomUUID(),
    title: "Welcome to Svelte Blog",
    slug: "welcome-to-svelte-blog",
    content: "This blog is built with Svelte 5 Runes — the most hyped frontend framework of 2026.\n\nIt runs self-hosted behind a CGNAT VPS gateway. No cloud. Hardware you own.",
    published: true,
    createdAt: Date.now(),
    updatedAt: Date.now()
  });
  posts.push({
    id: crypto.randomUUID(),
    title: "Why Svelte 5 Runes?",
    slug: "why-svelte-5-runes",
    content: "Svelte 5 introduces Runes — a new reactivity primitive that replaces $: reactive declarations.\n\n$state(), $derived(), $effect() make reactivity explicit, composable and framework-agnostic. No virtual DOM. Compiler outputs minimal vanilla JS. Bundles are tiny.",
    published: true,
    createdAt: Date.now() - 86400000,
    updatedAt: Date.now() - 86400000
  });
  save();
}

const guard = (req, res, next) => {
  if (req.headers["x-admin-token"] !== SECRET)
    return res.status(401).json({ error: "Unauthorized" });
  next();
};

app.get("/api/posts",      (_req, res) => res.json(posts.filter(p => p.published).sort((a,b) => b.createdAt - a.createdAt)));
app.get("/api/posts/:id",  (req, res) => { const p = posts.find(p => p.id === req.params.id); (!p || !p.published) ? res.status(404).json({error:"Not found"}) : res.json(p); });
app.get("/health",         (_req, res) => res.json({ status: "ok", posts: posts.length }));
app.get("/api/admin/posts", guard, (_req, res) => res.json(posts.sort((a,b) => b.createdAt - a.createdAt)));

app.post("/api/admin/posts", guard, (req, res) => {
  const { title, slug, content, published = false } = req.body;
  if (!title || !content) return res.status(400).json({ error: "title and content required" });
  const post = { id: crypto.randomUUID(), title, slug: slug || title.toLowerCase().replace(/[^a-z0-9]+/g,"-"), content, published, createdAt: Date.now(), updatedAt: Date.now() };
  posts.push(post); save(); res.status(201).json(post);
});

app.put("/api/admin/posts/:id", guard, (req, res) => {
  const idx = posts.findIndex(p => p.id === req.params.id);
  if (idx === -1) return res.status(404).json({ error: "Not found" });
  posts[idx] = { ...posts[idx], ...req.body, updatedAt: Date.now() };
  save(); res.json(posts[idx]);
});

app.delete("/api/admin/posts/:id", guard, (req, res) => {
  const idx = posts.findIndex(p => p.id === req.params.id);
  if (idx === -1) return res.status(404).json({ error: "Not found" });
  posts.splice(idx, 1); save(); res.sendStatus(204);
});

app.use(express.static(path.join(__dirname, "public")));
app.get("*", (_req, res) => res.sendFile(path.join(__dirname, "public", "index.html")));

app.listen(PORT, "0.0.0.0", () => console.log(`[svelte-blog] listening on :${PORT}`));
