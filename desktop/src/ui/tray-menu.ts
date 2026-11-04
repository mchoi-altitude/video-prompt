{
  const button = (id: string) => document.getElementById(id) as HTMLButtonElement;
  for (const b of document.querySelectorAll("button")) {
    b.onclick = () => vp.trayMenuAction(b.id);
  }
  vp.trayMenuInfo().then((info) => {
    button("stop").hidden = !info.canStop;
    button("record").disabled = info.busy;
    document.getElementById("count")!.textContent = String(info.count);
  });
  addEventListener("keydown", (e) => {
    if (e.key === "Escape") vp.trayMenuClose();
  });
}
