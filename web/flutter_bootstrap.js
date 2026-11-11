{{flutter_js}}
{{flutter_build_config}}

// Local MVP: retire only this app's legacy Flutter worker, then load fresh code.
(async () => {
  if ('serviceWorker' in navigator) {
    try {
      const scope = new URL('.', document.baseURI).href;
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(registrations.filter((item) => item.scope === scope)
        .map((item) => item.unregister()));
    } catch (_) {
      // Worker availability must not prevent the application from starting.
    }
  }
  for (const build of _flutter.buildConfig.builds) {
    if (build.mainJsPath) {
      const separator = build.mainJsPath.includes('?') ? '&' : '?';
      build.mainJsPath += `${separator}build=${Date.now()}`;
    }
  }
  await _flutter.loader.load();
})();
