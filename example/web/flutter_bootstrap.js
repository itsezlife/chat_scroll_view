{{flutter_js}}
{{flutter_build_config}}

// The loading screen of the pages Flutter's own bootstrap loads (`flutter
// run`, a plain `flutter build web`), made to look like the one the release
// bootstrap shows (`sw`, see tool/build_web.sh): the logo inside a progress
// ring, the title, what is loading. It follows Flutter's loader up to 90%,
// the app reports the rest (`updateLoadingProgress`, from main.dart), and it
// fades out with the first frame.
(() => {
  const accent = '#54a1db';
  const background = '#111418';
  const radius = 65;
  const circumference = 2 * Math.PI * radius;

  const style = document.createElement('style');
  style.textContent = `
    #app-loading {
      position: fixed;
      inset: 0;
      z-index: 999999;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      background: ${background};
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      animation: app-loading-in 0.6s ease-in;
      transition: opacity 0.3s ease;
    }
    #app-loading.is-done { opacity: 0; pointer-events: none; }
    @keyframes app-loading-in {
      from { opacity: 0; transform: translateY(20px); }
      to { opacity: 1; transform: translateY(0); }
    }
    #app-loading .ring {
      position: relative;
      width: 140px;
      height: 140px;
      margin-bottom: 2rem;
    }
    #app-loading svg { position: absolute; inset: 0; transform: rotate(-90deg); }
    #app-loading .track { stroke: rgba(255, 255, 255, 0.08); }
    #app-loading .progress {
      stroke: ${accent};
      stroke-linecap: round;
      transition: stroke-dashoffset 0.4s ease;
    }
    #app-loading img {
      position: absolute;
      inset: 22px;
      width: 96px;
      height: 96px;
      border-radius: 50%;
    }
    #app-loading .title {
      color: ${accent};
      font-size: 1.5rem;
      font-weight: 600;
      margin-bottom: 0.75rem;
    }
    #app-loading .status { color: #b0b0b0; font-size: 0.9rem; min-height: 1.2em; }
    #app-loading .percent { color: #7a7f87; font-size: 0.75rem; margin-top: 0.4rem; }
    #app-loading .status.is-error { color: #ff6b6b; }
    @media (max-width: 480px) {
      #app-loading .ring { width: 112px; height: 112px; margin-bottom: 1.5rem; }
      #app-loading svg { width: 112px; height: 112px; }
      #app-loading img { inset: 18px; width: 76px; height: 76px; }
      #app-loading .title { font-size: 1.25rem; }
    }
  `;
  document.head.append(style);

  const root = document.createElement('div');
  root.id = 'app-loading';
  root.setAttribute('role', 'progressbar');
  root.setAttribute('aria-valuemin', '0');
  root.setAttribute('aria-valuemax', '100');
  root.innerHTML = `
    <div class="ring">
      <svg viewBox="0 0 140 140" width="140" height="140" aria-hidden="true">
        <circle class="track" cx="70" cy="70" r="${radius}" fill="none" stroke-width="4"></circle>
        <circle class="progress" cx="70" cy="70" r="${radius}" fill="none" stroke-width="4"
          stroke-dasharray="${circumference}" stroke-dashoffset="${circumference}"></circle>
      </svg>
      <img src="icons/Icon-192.png" alt="">
    </div>
    <div class="title">Chat Scroll View</div>
    <div class="status"></div>
    <div class="percent"></div>
  `;
  const ring = root.querySelector('.progress');
  const status = root.querySelector('.status');
  const percentText = root.querySelector('.percent');

  let shown = 0;
  function render() {
    ring.setAttribute('stroke-dashoffset', String(circumference * (1 - shown / 100)));
    root.setAttribute('aria-valuenow', String(Math.round(shown)));
    percentText.textContent = `${Math.round(shown)}%`;
  }
  function show(percent, text) {
    // Progress never goes back.
    shown = Math.max(shown, Math.min(100, Number(percent) || 0));
    if (text) status.textContent = text;
    render();
  }

  // A stage that takes long (a debug build loads a thousand scripts) creeps
  // towards its ceiling, ever slower, so the ring never looks frozen and
  // never reaches the next stage before it starts.
  let ceiling = 0;
  const creep = setInterval(() => {
    if (shown >= ceiling - 0.5) return;
    shown += (ceiling - shown) * 0.04;
    render();
  }, 200);
  function stage(percent, until, text) {
    show(percent, text);
    ceiling = until;
  }

  let removed = false;
  function remove() {
    if (removed) return;
    removed = true;
    clearInterval(creep);
    root.classList.add('is-done');
    setTimeout(() => root.remove(), 300);
  }

  function fail(error) {
    console.error(error);
    clearInterval(creep);
    status.textContent = 'The app could not load. Reload the page to try again.';
    status.classList.add('is-error');
  }

  // The hooks the app reports its last steps through, as the release
  // bootstrap defines them.
  window.updateLoadingProgress = (percent, text) => stage(percent, percent, text);
  window.removeLoadingIndicator = remove;
  window.addEventListener('flutter-first-frame', remove, { once: true });

  const mount = () => {
    document.body.append(root);
    stage(5, 55, 'Loading application');
  };
  if (document.body) mount();
  else document.addEventListener('DOMContentLoaded', mount, { once: true });

  _flutter.loader.load({
    onEntrypointLoaded: async (engineInitializer) => {
      try {
        stage(60, 82, 'Initializing engine');
        const appRunner = await engineInitializer.initializeEngine();
        stage(85, 90, 'Starting application');
        await appRunner.runApp();
      } catch (error) {
        fail(error);
      }
    },
  }).catch(fail);
})();
