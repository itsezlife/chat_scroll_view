# passkeys web bundle

`bundle.js` is the WebAuthn bridge `passkeys_web` (via `supabase_flutter`)
calls on the web: the `bundle.js` asset of the
[corbado/flutter-passkeys](https://github.com/corbado/flutter-passkeys)
release 2.5.0, unchanged, under its BSD-3-Clause licence (`LICENSE`).

It is served with the app rather than from the GitHub release: a release
asset goes through a redirect that has taken a minute to answer, and the page
waited for it before anything else loaded. The pages load it with `async`;
nothing calls it before a passkey is asked for.

To update it, download the release's `bundle.js` over this one and change the
version above.
