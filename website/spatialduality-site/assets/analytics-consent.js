const storageKey = "spatialduality.analytics.optIn";
const token = "REPLACE_WITH_CLOUDFLARE_WEB_ANALYTICS_TOKEN";

function loadAnalytics() {
  if (!token || token.startsWith("REPLACE_WITH")) return;
  if (document.querySelector("script[data-cf-beacon]")) return;
  const script = document.createElement("script");
  script.defer = true;
  script.src = "https://static.cloudflareinsights.com/beacon.min.js";
  script.dataset.cfBeacon = JSON.stringify({ token });
  document.head.appendChild(script);
}

function setVisible(banner, visible) {
  banner.dataset.visible = visible ? "true" : "false";
}

window.addEventListener("DOMContentLoaded", () => {
  const choice = localStorage.getItem(storageKey);
  const banner = document.querySelector("[data-analytics-consent]");
  if (choice === "yes") {
    loadAnalytics();
    return;
  }
  if (!banner || choice === "no") return;
  setVisible(banner, true);
  banner.querySelector("[data-consent-yes]")?.addEventListener("click", () => {
    localStorage.setItem(storageKey, "yes");
    setVisible(banner, false);
    loadAnalytics();
  });
  banner.querySelector("[data-consent-no]")?.addEventListener("click", () => {
    localStorage.setItem(storageKey, "no");
    setVisible(banner, false);
  });
});
