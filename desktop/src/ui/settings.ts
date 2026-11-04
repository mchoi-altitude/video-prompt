{
  const retention = document.getElementById("retention") as HTMLSelectElement;
  const fade = document.getElementById("fade") as HTMLInputElement;

  const encode = (r: Prefs["retention"]) => (r === "never" ? "never" : "days" in r ? `days:${r.days}` : `last:${r.keepLast}`);
  const decode = (v: string): Prefs["retention"] => {
    if (v === "never") return "never";
    const [kind, n] = v.split(":");
    return kind === "days" ? { days: Number(n) } : { keepLast: Number(n) };
  };
  const save = () => void vp.settingsSet({ retention: decode(retention.value), drawingsFade: fade.checked });

  vp.settingsGet().then((s) => {
    retention.value = encode(s.retention);
    fade.checked = s.drawingsFade;
  });
  retention.onchange = save;
  fade.onchange = save;
}
