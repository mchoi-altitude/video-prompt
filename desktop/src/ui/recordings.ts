{
  const list = document.getElementById("list") as HTMLDivElement;

  const button = (label: string, onclick: () => void) => {
    const b = document.createElement("button");
    b.textContent = label;
    b.onclick = onclick;
    return b;
  };

  const render = async () => {
    const items = await vp.recordingsList();
    list.replaceChildren();
    if (!items.length) list.textContent = "No recordings yet.";
    for (const m of items) {
      const row = document.createElement("div");
      row.className = "row";
      const text = document.createElement("div");
      text.className = "text";
      const title = document.createElement("div");
      title.textContent = m.title;
      const sub = document.createElement("div");
      sub.className = "sub";
      const s = Math.round(m.duration);
      const when = new Date(m.createdAt).toLocaleString();
      sub.textContent = m.status === "processingFailed" ? `${when} · Processing failed` : `${when} · ${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
      text.append(title, sub);
      row.append(text);
      if (m.status === "processingFailed") row.append(button("Retry", () => void vp.recordingsRetry(m.id)));
      else if (m.status !== "processing") row.append(button("Copy reference", () => void vp.recordingsCopy(m.id)));
      row.append(button("Delete", () => void vp.recordingsDelete(m.id)));
      list.append(row);
    }
  };

  vp.onRecordingsChanged(() => void render());
  void render();
}
