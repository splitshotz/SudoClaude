importScripts("config.js");

const CFG = self.SUDOCLAUDE || { port: 47823, token: "" };
let ws = null;
const attached = new Set();
const detachTimers = {};
const refs = {};
const scales = {};

// ---- connection -------------------------------------------------------------

function connect() {
  if (ws && (ws.readyState === 0 || ws.readyState === 1)) return;
  try {
    ws = new WebSocket(`ws://127.0.0.1:${CFG.port}`);
  } catch (e) { return; }
  ws.onopen = () => ws.send(JSON.stringify({ role: "extension", token: CFG.token }));
  ws.onmessage = async (ev) => {
    let m;
    try { m = JSON.parse(ev.data); } catch (e) { return; }
    if (m.id === undefined) return;
    try {
      const result = await handle(m.cmd, m.args || {});
      ws.send(JSON.stringify({ id: m.id, result }));
    } catch (e) {
      ws.send(JSON.stringify({ id: m.id, error: String(e && e.message || e) }));
    }
  };
  ws.onclose = () => { ws = null; };
  ws.onerror = () => {};
}

// Exchanging messages keeps the service worker alive; the alarm brings it back.
setInterval(() => {
  if (ws && ws.readyState === 1) ws.send(JSON.stringify({ ping: Date.now() }));
  else connect();
}, 20000);
setInterval(() => { if (!ws) connect(); }, 3000);
chrome.alarms.create("sudoclaude-keepalive", { periodInMinutes: 0.5 });
chrome.alarms.onAlarm.addListener(() => connect());
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
connect();

// ---- debugger -----------------------------------------------------------------

async function attach(tabId) {
  if (!attached.has(tabId)) {
    await chrome.debugger.attach({ tabId }, "1.3");
    attached.add(tabId);
  }
  // Detach when idle so Chrome's "is debugging this browser" bar goes away.
  clearTimeout(detachTimers[tabId]);
  detachTimers[tabId] = setTimeout(() => {
    chrome.debugger.detach({ tabId }).catch(() => {});
    attached.delete(tabId);
  }, 20000);
}
chrome.debugger.onDetach.addListener((src) => attached.delete(src.tabId));

async function cdp(tabId, method, params = {}) {
  await attach(tabId);
  return chrome.debugger.sendCommand({ tabId }, method, params);
}

async function resolveTab(id) {
  if (id) return id;
  const [t] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (!t) throw new Error("no active tab");
  return t.id;
}

function waitLoaded(tabId, ms = 15000) {
  return new Promise((resolve) => {
    const done = () => { chrome.tabs.onUpdated.removeListener(fn); clearTimeout(t); resolve(); };
    const fn = (id, info) => { if (id === tabId && info.status === "complete") done(); };
    const t = setTimeout(done, ms);
    chrome.tabs.onUpdated.addListener(fn);
  });
}

// ---- page reading ---------------------------------------------------------------

const INTERACTIVE = new Set(["button", "link", "textbox", "searchbox", "combobox", "checkbox",
  "radio", "menuitem", "menuitemcheckbox", "menuitemradio", "tab", "switch", "slider",
  "option", "listbox", "spinbutton", "treeitem", "textField", "TextField"]);
const CONTEXT = new Set(["heading", "dialog", "alertdialog", "alert", "img", "navigation",
  "main", "form", "region", "table", "row", "cell", "columnheader", "list", "listitem"]);

async function snapshot(tabId, { query = "", all = false, max = 350 } = {}) {
  const { nodes } = await cdp(tabId, "Accessibility.getFullAXTree", {});
  const byId = new Map(nodes.map((n) => [n.nodeId, n]));
  const out = [];
  const map = {};
  let n = 0;
  const q = query.toLowerCase();
  const visit = (node, depth) => {
    if (!node || n >= max) return;
    const role = node.role && node.role.value || "";
    const name = (node.name && node.name.value || "").trim();
    let next = depth;
    if (!node.ignored) {
      let keep = INTERACTIVE.has(role) || (all && (CONTEXT.has(role) || (role === "StaticText" && name)))
        || (CONTEXT.has(role) && name && ["heading", "dialog", "alertdialog", "alert"].includes(role));
      if (q) keep = name.toLowerCase().includes(q);
      if (keep && node.backendDOMNodeId) {
        n += 1;
        const ref = "r" + n;
        map[ref] = node.backendDOMNodeId;
        const props = {};
        for (const p of node.properties || []) props[p.name] = p.value && p.value.value;
        const extra = [];
        if (node.value && node.value.value !== undefined && node.value.value !== "")
          extra.push(`value="${String(node.value.value).slice(0, 80)}"`);
        for (const k of ["checked", "selected", "expanded", "disabled", "focused", "required"])
          if (props[k] === true || props[k] === "true") extra.push(k);
        out.push(`${"  ".repeat(Math.min(depth, 10))}[${ref}] ${role} "${name.slice(0, 90)}"` +
          (extra.length ? " " + extra.join(" ") : ""));
        next = depth + 1;
      }
    }
    for (const c of node.childIds || []) visit(byId.get(c), next);
  };
  visit(nodes[0], 0);
  refs[tabId] = map;
  const tab = await chrome.tabs.get(tabId);
  return { tabId, title: tab.title, url: tab.url, elements: n,
           tree: out.join("\n") + (n >= max ? "\n… (limit reached; use query=)" : "") };
}

async function center(tabId, ref) {
  const id = (refs[tabId] || {})[ref];
  if (!id) throw new Error(`unknown ref ${ref}; read the page again`);
  await cdp(tabId, "DOM.scrollIntoViewIfNeeded", { backendNodeId: id }).catch(() => {});
  const { model } = await cdp(tabId, "DOM.getBoxModel", { backendNodeId: id });
  const q = model.border;
  return { x: (q[0] + q[2] + q[4] + q[6]) / 4, y: (q[1] + q[3] + q[5] + q[7]) / 4, id };
}

// ---- input --------------------------------------------------------------------------

const KEYS = {
  Enter: [13, "\r"], Tab: [9, "\t"], Escape: [27], Backspace: [8], Delete: [46],
  ArrowUp: [38], ArrowDown: [40], ArrowLeft: [37], ArrowRight: [39],
  Home: [36], End: [35], PageUp: [33], PageDown: [34], Space: [32, " "],
};

async function pressKey(tabId, combo) {
  const parts = combo.split("+");
  let key = parts.pop();
  const alias = { enter: "Enter", return: "Enter", esc: "Escape", escape: "Escape", tab: "Tab",
    backspace: "Backspace", delete: "Delete", up: "ArrowUp", down: "ArrowDown",
    left: "ArrowLeft", right: "ArrowRight", space: "Space", home: "Home", end: "End",
    pageup: "PageUp", pagedown: "PageDown" };
  key = alias[key.toLowerCase()] || key;
  let mods = 0;
  for (const m of parts.map((p) => p.toLowerCase())) {
    if (m === "alt") mods |= 1;
    if (m === "ctrl" || m === "control") mods |= 2;
    if (m === "meta" || m === "super" || m === "cmd") mods |= 4;
    if (m === "shift") mods |= 8;
  }
  const [code, text] = KEYS[key] || [key.length === 1 ? key.toUpperCase().charCodeAt(0) : 0,
    key.length === 1 && !(mods & 7) ? key : undefined];
  const base = { modifiers: mods, windowsVirtualKeyCode: code, key: key === "Space" ? " " : key,
    code: key.length === 1 ? "Key" + key.toUpperCase() : key };
  await cdp(tabId, "Input.dispatchKeyEvent", { type: text ? "keyDown" : "rawKeyDown", text, ...base });
  await cdp(tabId, "Input.dispatchKeyEvent", { type: "keyUp", ...base });
}

async function mouseClick(tabId, x, y, button = "left", clickCount = 1) {
  await cdp(tabId, "Input.dispatchMouseEvent", { type: "mouseMoved", x, y });
  for (let i = 1; i <= clickCount; i++) {
    await cdp(tabId, "Input.dispatchMouseEvent", { type: "mousePressed", x, y, button, clickCount: i });
    await cdp(tabId, "Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button, clickCount: i });
  }
}

// ---- commands -----------------------------------------------------------------------

async function handle(cmd, a) {
  switch (cmd) {
    case "ping": return "pong";
    case "tabs": {
      const tabs = await chrome.tabs.query({});
      return tabs.map((t) => ({ id: t.id, title: t.title, url: t.url, active: t.active, window: t.windowId }));
    }
    case "open": {
      const t = await chrome.tabs.create({ url: a.url, active: !!a.active });
      await waitLoaded(t.id);
      return { tabId: t.id };
    }
    case "navigate": {
      const tabId = await resolveTab(a.tabId);
      let url = a.url;
      if (url === "back") await chrome.tabs.goBack(tabId);
      else if (url === "forward") await chrome.tabs.goForward(tabId);
      else {
        if (!/^[a-z]+:/i.test(url)) url = "https://" + url;
        await chrome.tabs.update(tabId, { url });
      }
      await waitLoaded(tabId);
      const t = await chrome.tabs.get(tabId);
      return { tabId, title: t.title, url: t.url };
    }
    case "activate": {
      const t = await chrome.tabs.update(a.tabId, { active: true });
      await chrome.windows.update(t.windowId, { focused: true });
      return "ok";
    }
    case "close": await chrome.tabs.remove(a.tabId); return "ok";
    case "read": return snapshot(await resolveTab(a.tabId), a);
    case "text": {
      const tabId = await resolveTab(a.tabId);
      const [r] = await chrome.scripting.executeScript({ target: { tabId },
        func: (max) => (document.body ? document.body.innerText : "").slice(0, max), args: [a.max || 20000] });
      return r.result;
    }
    case "click": {
      const tabId = await resolveTab(a.tabId);
      let x = a.x, y = a.y;
      if (a.ref) ({ x, y } = await center(tabId, a.ref));
      else { const s = scales[tabId] || 1; x = x / s; y = y / s; }
      await mouseClick(tabId, x, y, a.button || "left", a.count || 1);
      return "clicked";
    }
    case "type": {
      const tabId = await resolveTab(a.tabId);
      if (a.ref) {
        const { id } = await center(tabId, a.ref);
        await cdp(tabId, "DOM.focus", { backendNodeId: id }).catch(async () => {
          const c = await center(tabId, a.ref); await mouseClick(tabId, c.x, c.y);
        });
      }
      if (a.clear) { await pressKey(tabId, "ctrl+a"); await pressKey(tabId, "Backspace"); }
      if (a.text) await cdp(tabId, "Input.insertText", { text: a.text });
      if (a.submit) await pressKey(tabId, "Enter");
      return "typed";
    }
    case "key": {
      const tabId = await resolveTab(a.tabId);
      for (const k of String(a.keys).split(" ").filter(Boolean)) await pressKey(tabId, k);
      return "pressed";
    }
    case "scroll": {
      const tabId = await resolveTab(a.tabId);
      let x = a.x || 400, y = a.y || 300;
      if (a.ref) ({ x, y } = await center(tabId, a.ref));
      await cdp(tabId, "Input.dispatchMouseEvent", { type: "mouseWheel", x, y, deltaX: a.dx || 0, deltaY: a.dy || 600 });
      return "scrolled";
    }
    case "screenshot": {
      const tabId = await resolveTab(a.tabId);
      const m = await cdp(tabId, "Page.getLayoutMetrics");
      const vw = m.cssVisualViewport.clientWidth, vh = m.cssVisualViewport.clientHeight;
      const scale = Math.min(1, (a.maxEdge || 1280) / Math.max(vw, vh));
      scales[tabId] = scale;
      const r = await cdp(tabId, "Page.captureScreenshot", { format: "jpeg", quality: 72,
        clip: { x: m.cssVisualViewport.pageX, y: m.cssVisualViewport.pageY, width: vw, height: vh, scale } });
      return { tabId, data: r.data, width: Math.round(vw * scale), height: Math.round(vh * scale) };
    }
    case "eval": {
      const tabId = await resolveTab(a.tabId);
      const r = await cdp(tabId, "Runtime.evaluate", { expression: a.js, returnByValue: true, awaitPromise: true });
      if (r.exceptionDetails) throw new Error(r.exceptionDetails.text || "script error");
      return r.result && r.result.value;
    }
    default: throw new Error("unknown command " + cmd);
  }
}
