// Keep this filename versioned. Chromium caches service workers for extensions
// loaded via --load-extension, so a new URL forces registration of new code.

const NATIVE_HOST = "com.omarchy.parent_llm";
const recent = new Map();
const DEDUPE_MS = 60000;

function keyOf(msg) {
  return [msg.host || "", (msg.prompt || "").trim()].join("\n");
}

function shouldSend(msg) {
  const prompt = (msg && msg.prompt) || "";
  if (!prompt.trim()) return false;
  const key = keyOf(msg);
  const now = Date.now();
  const last = recent.get(key) || 0;
  if (now - last < DEDUPE_MS) return false;
  recent.set(key, now);
  if (recent.size > 200) {
    for (const [k, t] of recent) {
      if (now - t > DEDUPE_MS) recent.delete(k);
    }
  }
  return true;
}

chrome.runtime.onMessage.addListener((msg) => {
  if (!msg || msg.type !== "omarchy-parent-llm") return;
  if (!shouldSend(msg)) return;
  const payload = {
    source: "browser",
    host: msg.host || "",
    url: msg.url || "",
    prompt: msg.prompt,
    attachments: Number(msg.attachments) || 0
  };
  chrome.runtime.sendNativeMessage(NATIVE_HOST, payload, () => {
    void chrome.runtime.lastError;
  });
});
