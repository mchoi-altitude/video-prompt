{
  const button = (id: string) => document.getElementById(id) as HTMLButtonElement;
  for (const b of document.querySelectorAll("button")) {
    b.onclick = () => vp.trayMenuAction(b.id);
  }
  vp.trayMenuInfo().then((info) => {
    button("stop").hidden = !info.canStop;
    button("record").hidden = vp.isWindows;
    button("screen").hidden = !vp.isWindows;
    button("area").hidden = !vp.isWindows;
    for (const id of ["record", "screen", "area"]) button(id).disabled = info.busy;
    document.getElementById("count")!.textContent = String(info.count);
  });
  addEventListener("keydown", (e) => {
    if (e.key === "Escape") vp.trayMenuClose();
  });
}
