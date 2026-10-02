export type TurnstileApi = {
  render: (element: HTMLElement, options: Record<string, unknown>) => string;
  reset: (widgetId: string) => void;
  remove: (widgetId: string) => void;
};

/** One widget owns one DOM element; callbacks from removed widgets are ignored. */
export function mountTurnstile(api: TurnstileApi, host: HTMLElement, siteKey: string,
  action: string, onToken: (token: string) => void) {
  let active = true;
  const setToken = (value: string) => { if (active) onToken(value); };
  onToken("");
  const id = api.render(host, {
    sitekey: siteKey, action, appearance: "interaction-only", size: "flexible", theme: "light",
    callback: setToken,
    "expired-callback": () => setToken(""),
    "error-callback": () => setToken(""),
  });
  return {
    reset() { if (active) { setToken(""); api.reset(id); } },
    dispose() { if (active) { active = false; api.remove(id); } },
  };
}
