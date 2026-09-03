window.addEventListener("message", (event) => {
  if (event.source !== window) return;
  const data = event.data;
  if (!data || data.type !== "omarchy-parent-llm") return;
  chrome.runtime.sendMessage({
    type: "omarchy-parent-llm",
    host: data.host || location.hostname,
    url: data.url || location.href,
    prompt: data.prompt,
    attachments: data.attachments || 0
  });
});
