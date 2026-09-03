(() => {
  const MAX = 32 * 1024;
  const TOKEN = "omarchy-parent-llm";

  function hostOf() {
    return location.hostname.replace(/^www\./, "");
  }

  function emit(prompt, url, attachments) {
    const text = String(prompt || "").trim();
    if (!text || text.length > MAX) return;
    window.postMessage({
      type: TOKEN,
      host: hostOf(),
      url: stripQuery(url || location.href),
      prompt: text,
      attachments: attachments || 0
    }, "*");
  }

  function stripQuery(url) {
    try {
      const parsed = new URL(url, location.href);
      parsed.search = "";
      parsed.hash = "";
      return parsed.toString();
    } catch (e) {
      return String(url || "").split("?")[0];
    }
  }

  function textOf(value) {
    if (value == null) return "";
    if (typeof value === "string") return value;
    if (typeof value === "number") return "";
    if (Array.isArray(value)) {
      return value.map(textOf).filter(Boolean).join("\n");
    }
    if (typeof value !== "object") return "";
    if (value.type === "tool_result" || value.type === "tool_use") return "";
    if (typeof value.text === "string") return value.text;
    if (typeof value.value === "string") return value.value;
    if (Array.isArray(value.parts)) return textOf(value.parts);
    if (value.content != null) return textOf(value.content);
    return "";
  }

  function roleOf(message) {
    if (!message || typeof message !== "object") return "";
    const author = message.author;
    const role = message.role || (author && author.role) || message.type || "";
    return String(role).toLowerCase();
  }

  function lastUserMessage(messages) {
    if (!Array.isArray(messages)) return "";
    for (let i = messages.length - 1; i >= 0; i--) {
      const message = messages[i];
      const role = roleOf(message);
      if (role === "user" || role === "human") return textOf(message);
    }
    return "";
  }

  function fromObject(obj, depth) {
    if (!obj || depth > 6) return "";
    if (typeof obj === "string") return obj.length <= MAX ? obj : "";
    if (typeof obj !== "object") return "";

    if (typeof obj.prompt === "string") return obj.prompt;
    if (typeof obj.query === "string") return obj.query;
    if (typeof obj.input === "string") return obj.input;
    if (typeof obj.question === "string") return obj.question;
    if (typeof obj.text === "string" && (obj.role === "user" || obj.type === "user")) {
      return obj.text;
    }

    const user = lastUserMessage(obj.messages || obj.contents || obj.conversation);
    if (user) return user;

    if (Array.isArray(obj.contents)) {
      const gemini = lastUserMessage(obj.contents);
      if (gemini) return gemini;
    }

    return "";
  }

  function extract(raw) {
    if (typeof raw !== "string" || !raw) return "";
    if (raw.length > MAX * 4) return "";
    try {
      return fromObject(JSON.parse(raw), 0).trim();
    } catch (e) {
      return "";
    }
  }

  function inspectRequest(input, init) {
    const url = typeof input === "string" ? input : (input && input.url) || "";
    const method = ((init && init.method) || (input && input.method) || "GET").toUpperCase();
    if (method !== "POST" && method !== "PUT") return;
    let body = init && init.body;
    if (typeof body !== "string") return;
    const prompt = extract(body);
    if (prompt) emit(prompt, url);
  }

  const origFetch = window.fetch;
  if (typeof origFetch === "function") {
    window.fetch = function (input, init) {
      try {
        inspectRequest(input, init);
      } catch (e) {
        /* never break the page */
      }
      return origFetch.apply(this, arguments);
    };
  }

  const origOpen = XMLHttpRequest.prototype.open;
  const origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url) {
    this.__omarchyLlmMethod = method;
    this.__omarchyLlmUrl = url;
    return origOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function (body) {
    try {
      if (typeof body === "string") {
        inspectRequest(this.__omarchyLlmUrl, { method: this.__omarchyLlmMethod, body });
      }
    } catch (e) {
      /* never break the page */
    }
    return origSend.apply(this, arguments);
  };

  document.addEventListener("keydown", (event) => {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return;
    const el = event.target;
    if (!el) return;
    const tag = (el.tagName || "").toLowerCase();
    const editable = el.isContentEditable || tag === "textarea";
    if (!editable) return;
    const text = (el.value || el.innerText || "").trim();
    if (!text) return;
    emit(text, location.href);
  }, true);
})();
