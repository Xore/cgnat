package main

// loginPage is the full HTML for the gate. Two placeholders are substituted
// at render time:
//
//	{{NEXT}}   the (escaped) `next` path, placed in a hidden field
//	{{ERROR}}  an optional error block
//
// Styling is inlined so the gateway has zero static-file dependencies and
// matches the xore theme used by the blog behind it.
const loginPage = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>xore//gate</title>
<style>
  :root {
    --bg:#06080b; --panel:#0c1119; --line:rgba(255,255,255,.11);
    --text:#e8edf3; --muted:#8a97a8; --cyan:#38bdf8; --green:#34d399; --red:#f87171;
    --mono:"JetBrains Mono",ui-monospace,monospace;
    --font:"Inter",system-ui,sans-serif;
  }
  * { box-sizing:border-box; margin:0; padding:0; }
  body {
    min-height:100vh; display:flex; align-items:center; justify-content:center;
    font-family:var(--font); color:var(--text);
    background:radial-gradient(120% 80% at 50% -10%,#131a24 0%,#090c11 55%,#06080b 100%);
    padding:24px;
  }
  .gate {
    width:100%; max-width:400px;
    background:linear-gradient(180deg,#0c1119,#080b10);
    border:1px solid var(--line); border-radius:14px; padding:32px;
  }
  .brand {
    display:flex; align-items:center; gap:10px; justify-content:center;
    margin-bottom:6px; font-weight:800; letter-spacing:.12em; font-size:1.1rem;
  }
  .brand span { color:var(--cyan); }
  .sub {
    text-align:center; font-family:var(--mono); font-size:.7rem;
    letter-spacing:.1em; color:var(--muted); text-transform:uppercase;
    margin-bottom:26px;
  }
  label {
    display:block; font-family:var(--mono); font-size:.72rem; letter-spacing:.08em;
    color:var(--muted); text-transform:uppercase; margin:0 0 6px;
  }
  input {
    width:100%; background:#080b10; border:1px solid var(--line); border-radius:8px;
    color:var(--text); font-family:var(--mono); font-size:.9rem; padding:11px 14px;
    outline:none; margin-bottom:16px; transition:border-color .2s;
  }
  input:focus { border-color:rgba(56,189,248,.5); }
  button {
    width:100%; font-family:var(--mono); font-size:.8rem; letter-spacing:.08em;
    padding:12px; border-radius:8px; cursor:pointer;
    background:rgba(56,189,248,.12); border:1px solid rgba(56,189,248,.35); color:var(--cyan);
    transition:background .2s,border-color .2s;
  }
  button:hover { background:rgba(56,189,248,.2); border-color:var(--cyan); }
  .err {
    font-family:var(--mono); font-size:.75rem; color:var(--red);
    margin-bottom:16px; text-align:center;
  }
  .foot {
    margin-top:22px; text-align:center; font-family:var(--mono); font-size:.66rem;
    letter-spacing:.08em; color:var(--muted); text-transform:uppercase;
  }
  .led {
    display:inline-block; width:7px; height:7px; border-radius:50%;
    background:var(--green); box-shadow:0 0 10px var(--green); margin-right:6px;
    vertical-align:middle;
  }
</style>
</head>
<body>
  <form class="gate" method="post" action="/_auth/login">
    <div class="brand">XORE<span>//</span>GATE</div>
    <div class="sub"><span class="led"></span>restricted area</div>
    <input type="hidden" name="next" value="{{NEXT}}">
    {{ERROR}}
    <label for="u">username</label>
    <input id="u" name="username" autocomplete="username" autofocus>
    <label for="p">password</label>
    <input id="p" name="password" type="password" autocomplete="current-password">
    <button type="submit">authenticate</button>
    <div class="foot">cgnat gateway &bull; no open ports</div>
  </form>
</body>
</html>`
