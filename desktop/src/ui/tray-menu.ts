{
  const button = (id: string) => document.getElementById(id) as HTMLButtonElement;
  for (const b of document.querySelectorAll("button")) {
    b.onclick = () => vp.trayMenuAction(b.id);
  }
  vp.trayMenuInfo().then((info) => {
    button("stop").hidden = !info.canStop;
    button("record").disabled = info.busy;
    // Windows: two modes, like the Mac. The last one used is checked, and the shortcut starts it.
    if (info.twoModes) {
      button("record").hidden = true;
      for (const [id, mode] of [["record-screen", "screen"], ["record-area", "area"]] as const) {
        const b = button(id);
        b.hidden = false;
        b.disabled = info.busy;
        b.classList.toggle("checked", info.lastMode === mode);
        b.querySelector(".hint")!.textContent = info.lastMode === mode ? "Ctrl+Alt+Shift+R" : "";
      }
    }
    document.getElementById("count")!.textContent = String(info.count);
  });
  addEventListener("keydown", (e) => {
    if (e.key === "Escape") vp.trayMenuClose();
  });
}
