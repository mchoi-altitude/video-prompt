// Same layout and wording as Sources/VideoPrompt/RecordingsWindow.swift and VPApp/RecordingsModel.swift.
{
  const el = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
  const list = el<HTMLDivElement>("list");
  const usage = el<HTMLSpanElement>("usage");
  const retention = el<HTMLSelectElement>("retention");
  const deleteSelected = el<HTMLButtonElement>("delete-selected");
  const selected = new Set<string>();
  let prefs: Prefs = { retention: { days: 3 }, drawingsFade: true };
  let items: Meta[] = [];

  const encode = (r: Prefs["retention"]) => (r === "never" ? "never" : "days" in r ? `days:${r.days}` : `last:${r.keepLast}`);
  const decode = (v: string): Prefs["retention"] => {
    if (v === "never") return "never";
    const [kind, n] = v.split(":");
    return kind === "days" ? { days: Number(n) } : { keepLast: Number(n) };
  };

  const megabytes = (bytes: number) => `${(bytes / 1_000_000).toFixed(1)} MB`;

  const statusText = (m: Meta) => {
    if (m.status === "processing") return "Processing…";
    if (m.status === "reviewing") return "In review";
    if (m.status === "processingFailed") return "Processing failed · Retry";
    return "Saved";
  };

  const expiryText = (m: Meta) => {
    const r = prefs.retention;
    if (r === "never" || !("days" in r)) return null;
    const remaining = r.days * 86400_000 - (Date.now() - Date.parse(m.createdAt));
    if (remaining <= 86400_000) return "Auto-deletes within a day";
    return `Auto-deletes in ${Math.ceil(remaining / 86400_000)} days`;
  };

  const whenText = (m: Meta) => {
    const s = Math.floor(m.duration);
    const when = new Date(m.createdAt).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
    return `${when} · ${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
  };

  const div = (className: string, text = "") => {
    const d = document.createElement("div");
    d.className = className;
    d.textContent = text;
    return d;
  };

  const button = (label: string, onclick: (b: HTMLButtonElement) => void) => {
    const b = document.createElement("button");
    b.textContent = label;
    b.onclick = () => onclick(b);
    return b;
  };

  const updateSelection = () => {
    deleteSelected.disabled = selected.size === 0;
    deleteSelected.textContent = selected.size ? `Delete ${selected.size} selected` : "Delete selected";
  };

  const action = (m: Meta) => {
    if (m.status === "processingFailed") return button("Retry", () => void vp.recordingsRetry(m.id));
    if (m.status === "reviewing") return button("Review", () => vp.recordingsReview(m.id));
    if (m.status === "processing") return div("");
    return button("Copy reference", (b) => {
      void vp.recordingsCopy(m.id);
      b.textContent = "Copied ✓";
      setTimeout(() => (b.textContent = "Copy reference"), 1500);
    });
  };

  const row = (m: Meta) => {
    const r = div("row");
    const check = document.createElement("input");
    check.type = "checkbox";
    check.checked = selected.has(m.id);
    check.setAttribute("aria-label", `Select ${m.title}`);
    check.onchange = () => {
      if (check.checked) selected.add(m.id);
      else selected.delete(m.id);
      updateSelection();
    };

    const thumb = document.createElement("img");
    thumb.className = "thumb";
    thumb.alt = "";
    if (m.status !== "processing" && m.status !== "processingFailed") thumb.src = m.overview;

    const text = div("text");
    text.append(div("title", m.title), div("sub", whenText(m)));

    const state = div("state");
    state.append(div("", statusText(m)));
    const expiry = expiryText(m);
    if (expiry) state.append(div("expires", expiry));

    const act = div("action");
    act.append(action(m));

    const trash = document.createElement("button");
    trash.className = "trash";
    trash.title = "Move to Trash";
    trash.setAttribute("aria-label", `Delete ${m.title}`);
    trash.innerHTML = '<svg viewBox="0 0 24 24"><path d="M4 7h16M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2M6.5 7l1 12a1.5 1.5 0 0 0 1.5 1.4h6a1.5 1.5 0 0 0 1.5-1.4l1-12M10 11v5M14 11v5" /></svg>';
    trash.onclick = () => void vp.recordingsDelete(m.id);

    r.append(check, thumb, text, state, div("size", megabytes(m.sizeBytes)), act);
    if (vp.isWindows && m.status === "ready") {
      r.append(button("WSL path", (b) => {
        void vp.recordingsCopyWsl(m.id);
        b.textContent = "Copied ✓";
        setTimeout(() => (b.textContent = "WSL path"), 1500);
      }));
    }
    r.append(trash);
    return r;
  };

  const render = async () => {
    [items, prefs] = await Promise.all([vp.recordingsList(), vp.settingsGet()]);
    const ids = new Set(items.map((m) => m.id));
    for (const id of selected) if (!ids.has(id)) selected.delete(id);
    retention.value = encode(prefs.retention);
    const total = items.reduce((sum, m) => sum + m.sizeBytes, 0);
    usage.textContent = `${items.length} ${items.length === 1 ? "recording" : "recordings"} · ${megabytes(total)}`;
    list.replaceChildren();
    if (items.length) list.append(...items.map(row));
    else {
      const empty = div("quiet", "No recordings. New ones show up here after you press Stop.");
      empty.id = "empty";
      list.append(empty);
    }
    updateSelection();
  };

  retention.onchange = () => void vp.settingsSet({ ...prefs, retention: decode(retention.value) });
  el("select-all").onclick = () => {
    for (const m of items) selected.add(m.id);
    void render();
  };
  deleteSelected.onclick = async () => {
    for (const id of [...selected]) await vp.recordingsDelete(id);
    selected.clear();
    void render();
  };
  vp.onRecordingsChanged(() => void render());
  void render();
}
