#!/usr/bin/env bash
# The release web build: the app, the release index.html, and the `sw`
# service worker and bootstrap (a loading widget the app finishes, CanvasKit
# from the CDN with a local fallback, an offline-ready cache).
#
#   tool/build_web.sh   # → build/web
#
# Serve index.html, bootstrap.js and sw.js with `Cache-Control: no-cache`
# (everything else may be cached for good: the worker's manifest invalidates
# it by hash), or a visitor can stay on an old build.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build web --release --base-href=/ -o build/web
rm -f build/web/index.html
mv build/web/index.prod.html build/web/index.html

# Pinned: sw.js and bootstrap.js are the app's boot path, so a new template
# arrives through a reviewed bump.
dart pub global activate sw 0.2.0
dart pub global run sw:generate --version="$(git rev-parse --short=8 HEAD)"
