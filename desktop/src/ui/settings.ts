{
  const fade = document.getElementById("fade") as HTMLInputElement;
  let prefs: Prefs;

  vp.settingsGet().then((s) => {
    prefs = s;
    fade.checked = s.drawingsFade;
  });
  fade.onchange = () => void vp.settingsSet({ ...prefs, drawingsFade: fade.checked });
}
