{{flutter_js}}
{{flutter_build_config}}

// Remove any service worker left by the previous TeamZone web release. A
// controlled page needs one reload before network assets are used directly.
(async () => {
  if ('serviceWorker' in navigator) {
    const registrations = await navigator.serviceWorker.getRegistrations();
    await Promise.all(registrations.map((registration) => registration.unregister()));
    if (navigator.serviceWorker.controller &&
        sessionStorage.getItem('teamzone-sw-retired') !== 'true') {
      sessionStorage.setItem('teamzone-sw-retired', 'true');
      location.reload();
      return;
    }
  }
  _flutter.loader.load();
})();
