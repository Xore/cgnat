"use strict";

/* xore//blog — framework-free SPA over the shared blog API contract.
   Every backend in cgnat/examples serves the same endpoints, so this file
   is byte-identical across examples. Configure via window.BLOG in index.html:
     stack:    label shown in the meta bar + footer (e.g. "PYTHON · FLASK")
     readOnly: true = no admin UI, posts come from a static posts.json
*/

const CFG = window.BLOG || {};
const READ_ONLY = !!CFG.readOnly;

let token = sessionStorage.getItem("xore-admin") || null;

const $ = (sel) => document.querySelector(sel);
const esc = (s) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[c]));
const fmt = (t) => new Date(Number(t)).toLocaleDateString();

/* ---------- chrome (marquee, stack tag, admin badge) ---------- */
const TICKER = [
  "SELF-HOSTED", "NO CLOUD", "HARDWARE I OWN", "HEINSBERG, DE",
  "ZERO-TRUST", "NO OPEN PORTS", "CGNAT GATEWAY", "JUST CONFIGS & PACKETS",
];

function chrome() {
  if (CFG.stack) {
    $("#stack-tag").textContent = CFG.stack;
    $("#footer-stack").textContent = CFG.stack.toLowerCase();
  }
  $("#marquee-track").innerHTML = [...TICKER, ...TICKER]
    .map((t) => `<span class="marquee__item">${esc(t)}</span><span class="marquee__dia">◆</span>`)
    .join("");
  if (READ_ONLY) $("#nav-admin").remove();
  syncBadge();
}

function syncBadge() {
  $("#admin-badge").hidden = !token;
}

/* ---------- toasts ---------- */
function toast(msg, ok = true) {
  const el = document.createElement("div");
  el.className = "toast " + (ok ? "toast-ok" : "toast-err");
  el.textContent = msg;
  $("#toasts").appendChild(el);
  setTimeout(() => el.remove(), 3200);
}

/* ---------- API ---------- */
async function api(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: {
      ...(body ? { "Content-Type": "application/json" } : {}),
      ...(token ? { "X-Admin-Token": token } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 204) return null;
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || "HTTP " + res.status);
  return data;
}

async function fetchPublicPosts() {
  if (!READ_ONLY) return api("GET", "/api/posts");
  const posts = await api("GET", "posts.json");
  return posts
    .filter((p) => p.published !== false)
    .sort((a, b) => b.createdAt - a.createdAt);
}

async function fetchPublicPost(id) {
  if (!READ_ONLY) return api("GET", "/api/posts/" + encodeURIComponent(id));
  const p = (await fetchPublicPosts()).find((x) => String(x.id) === String(id));
  if (!p) throw new Error("Not found");
  return p;
}

/* ---------- view switching ---------- */
const VIEWS = ["posts", "post", "admin", "form"];

function show(name) {
  for (const v of VIEWS) $("#view-" + v).classList.toggle("active", v === name);
  $("#nav-posts").classList.toggle("active", name === "posts" || name === "post");
  const adm = $("#nav-admin");
  if (adm) adm.classList.toggle("active", name === "admin" || name === "form");
  window.scrollTo(0, 0);
}

function errorBlock(view, title, msg) {
  view.innerHTML = `<h1 class="page-title">${esc(title)}</h1>
    <div class="empty"><div class="empty__icon">⚠</div><h3>error</h3><p>${esc(msg)}</p></div>`;
}

/* ---------- public: posts list ---------- */
async function renderPosts() {
  const view = $("#view-posts");
  show("posts");
  view.innerHTML = `<h1 class="page-title">posts</h1><p class="post-card__meta">loading…</p>`;
  try {
    const posts = await fetchPublicPosts();
    if (!posts.length) {
      view.innerHTML = `<h1 class="page-title">posts</h1>
        <div class="empty"><div class="empty__icon">∅</div>
          <h3>no posts yet</h3>
          <p>${READ_ONLY ? "add entries to posts.json" : "log in via ADMIN and write one"}</p>
        </div>`;
      return;
    }
    view.innerHTML = `<h1 class="page-title">posts</h1><div class="post-grid">`
      + posts.map((p) => `
        <a class="post-card" href="#/post/${encodeURIComponent(p.id)}">
          <div class="post-card__title">${esc(p.title)}</div>
          <div class="post-card__meta">${fmt(p.createdAt)}${p.slug ? " · " + esc(p.slug) : ""}</div>
          <div class="post-card__excerpt">${esc(p.content)}</div>
          <div class="post-card__arrow">read <span>→</span></div>
        </a>`).join("")
      + `</div>`;
  } catch (e) {
    errorBlock(view, "posts", e.message);
  }
}

/* ---------- public: single post ---------- */
async function renderPost(id) {
  const view = $("#view-post");
  show("post");
  view.innerHTML = `<p class="post-card__meta">loading…</p>`;
  try {
    const p = await fetchPublicPost(id);
    view.innerHTML = `
      <button class="post-single__back" id="back-btn">← all posts</button>
      <h1 class="post-single__title">${esc(p.title)}</h1>
      <div class="post-single__meta">${fmt(p.createdAt)}${p.slug ? " · " + esc(p.slug) : ""}</div>
      <div class="post-single__body">${esc(p.content)}</div>`;
    $("#back-btn").addEventListener("click", () => { location.hash = "/"; });
  } catch (e) {
    errorBlock(view, "post", e.message);
  }
}

/* ---------- admin: gate + table ---------- */
async function renderAdmin() {
  if (READ_ONLY) return renderPosts();
  const view = $("#view-admin");
  show("admin");

  if (!token) {
    view.innerHTML = `
      <div class="admin-gate">
        <h2 class="admin-gate__title">// admin access</h2>
        <form id="login-form">
          <div class="form-group">
            <label class="form-label" for="pw">password</label>
            <input id="pw" class="form-input" type="password" autocomplete="current-password" />
          </div>
          <p id="login-err" class="post-card__meta" style="color: var(--red)" hidden></p>
          <button class="btn btn-primary" type="submit" style="width: 100%">authenticate</button>
        </form>
      </div>`;
    $("#login-form").addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const err = $("#login-err");
      err.hidden = true;
      try {
        const { token: t } = await api("POST", "/api/admin/login", { password: $("#pw").value });
        token = t;
        sessionStorage.setItem("xore-admin", t);
        syncBadge();
        toast("authenticated");
        renderAdmin();
      } catch (e) {
        err.textContent = e.message;
        err.hidden = false;
      }
    });
    return;
  }

  view.innerHTML = `<p class="post-card__meta">loading…</p>`;
  let posts;
  try {
    posts = await api("GET", "/api/admin/posts");
  } catch (e) {
    // Token no longer valid (e.g. password changed) — back to the gate
    token = null;
    sessionStorage.removeItem("xore-admin");
    syncBadge();
    toast(e.message, false);
    return renderAdmin();
  }

  const rows = posts.map((p) => `
    <tr>
      <td>${esc(p.title)}</td>
      <td>${p.published
        ? `<span class="badge badge-green">published</span>`
        : `<span class="badge badge-muted">draft</span>`}</td>
      <td>${fmt(p.createdAt)}</td>
      <td>
        <div class="row-actions">
          <a class="btn btn-ghost" href="#/admin/edit/${encodeURIComponent(p.id)}">edit</a>
          <button class="btn btn-danger" data-del="${esc(p.id)}">del</button>
        </div>
      </td>
    </tr>`).join("");

  view.innerHTML = `
    <div class="admin-header">
      <h1 class="page-title" style="margin: 0">admin · posts</h1>
      <div class="row-actions">
        <a class="btn btn-primary" href="#/admin/new">+ new post</a>
        <button class="btn btn-ghost" id="logout-btn">logout</button>
      </div>
    </div>
    ${posts.length === 0
      ? `<div class="empty"><div class="empty__icon">∅</div><h3>no posts</h3><p>create your first post</p></div>`
      : `<div class="post-table"><table>
          <thead><tr><th>title</th><th>status</th><th>created</th><th>actions</th></tr></thead>
          <tbody>${rows}</tbody>
        </table></div>`}`;

  $("#logout-btn").addEventListener("click", () => {
    token = null;
    sessionStorage.removeItem("xore-admin");
    syncBadge();
    renderAdmin();
  });
  for (const btn of view.querySelectorAll("[data-del]")) {
    btn.addEventListener("click", async () => {
      if (!confirm("delete this post?")) return;
      try {
        await api("DELETE", "/api/admin/posts/" + encodeURIComponent(btn.dataset.del));
        toast("post deleted");
        renderAdmin();
      } catch (e) {
        toast(e.message, false);
      }
    });
  }
}

/* ---------- admin: create / edit form ---------- */
async function renderForm(id) {
  if (READ_ONLY) return renderPosts();
  if (!token) { location.hash = "/admin"; return; }
  const view = $("#view-form");
  show("form");

  view.innerHTML = `
    <div class="form-panel">
      <div class="form-panel__header">
        <h1 class="page-title" style="margin: 0">${id ? "edit post" : "new post"}</h1>
        <a class="btn btn-ghost" href="#/admin">← cancel</a>
      </div>
      <form id="post-form">
        <div class="form-row">
          <div class="form-group">
            <label class="form-label" for="f-title">title</label>
            <input id="f-title" class="form-input" />
          </div>
          <div class="form-group">
            <label class="form-label" for="f-slug">slug</label>
            <input id="f-slug" class="form-input" />
          </div>
        </div>
        <div class="form-group">
          <label class="form-label" for="f-content">content</label>
          <textarea id="f-content" class="form-textarea"></textarea>
        </div>
        <label class="form-check">
          <input id="f-published" type="checkbox" />
          <span>published</span>
        </label>
        <p id="form-err" class="post-card__meta" style="color: var(--red); margin-top: 12px" hidden></p>
        <div class="row-actions" style="margin-top: 20px">
          <button class="btn btn-primary" type="submit" id="save-btn">save</button>
          <a class="btn btn-ghost" href="#/admin">cancel</a>
        </div>
      </form>
    </div>`;

  let slugTouched = false;

  if (id) {
    try {
      const posts = await api("GET", "/api/admin/posts");
      const p = posts.find((x) => String(x.id) === String(id));
      if (p) {
        $("#f-title").value = p.title;
        $("#f-slug").value = p.slug || "";
        $("#f-content").value = p.content;
        $("#f-published").checked = !!p.published;
        slugTouched = true;
      }
    } catch (e) {
      toast(e.message, false);
    }
  }

  // Auto-generate the slug from the title until the user edits it by hand.
  $("#f-title").addEventListener("input", () => {
    if (slugTouched) return;
    $("#f-slug").value = $("#f-title").value
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");
  });
  $("#f-slug").addEventListener("input", () => { slugTouched = true; });

  $("#post-form").addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const err = $("#form-err");
    err.hidden = true;
    const body = {
      title: $("#f-title").value.trim(),
      slug: $("#f-slug").value.trim(),
      content: $("#f-content").value,
      published: $("#f-published").checked,
    };
    if (!body.title || !body.content.trim()) {
      err.textContent = "title and content required";
      err.hidden = false;
      return;
    }
    $("#save-btn").disabled = true;
    try {
      if (id) await api("PUT", "/api/admin/posts/" + encodeURIComponent(id), body);
      else await api("POST", "/api/admin/posts", body);
      toast("post saved");
      location.hash = "/admin";
    } catch (e) {
      err.textContent = e.message;
      err.hidden = false;
      $("#save-btn").disabled = false;
    }
  });
}

/* ---------- router ---------- */
function route() {
  const h = location.hash.replace(/^#/, "") || "/";
  let m;
  if (h === "/") return renderPosts();
  if ((m = h.match(/^\/post\/(.+)$/))) return renderPost(decodeURIComponent(m[1]));
  if (h === "/admin") return renderAdmin();
  if (h === "/admin/new") return renderForm(null);
  if ((m = h.match(/^\/admin\/edit\/(.+)$/))) return renderForm(decodeURIComponent(m[1]));
  return renderPosts();
}

window.addEventListener("hashchange", route);
chrome();
route();
