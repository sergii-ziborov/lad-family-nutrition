# Closed recipe API (pilot)

The iPhone app bundles its public demo recipes. This API reads private recipes from a JSON file **outside this public repository**, and returns them only to a client with a high-entropy bearer token. The app stores the token in the device Keychain. Server source code is public; recipe data and credentials are not.

`GET /v1/recipes` requires `Authorization: Bearer <token>`. It returns a JSON object matching [private-recipes.schema.json](private-recipes.schema.json). `GET /healthz` is unauthenticated for loopback monitoring only. All responses use `Cache-Control: no-store`. The server binds only to `127.0.0.1`; a separate HTTPS reverse proxy is required for an iPhone to connect. Never expose port 9823 directly to the internet.

To prepare a pilot instance:

1. Choose a dedicated HTTPS hostname and reverse-proxy route. Do not reuse an unrelated production app's URL or credentials.
2. Create a dedicated non-privileged service user and private data directory such as `/var/lib/lad-recipes`, readable only by that service user. Put the real catalog in `/var/lib/lad-recipes/private-recipes.json`, beginning with `{"recipes":[]}` until reviewed content exists. Do not put this file in Git or a public Docker image.
3. Generate a random token with `openssl rand -hex 32`. Store its SHA-256 digest, not the raw token, in the service environment variable `LAD_TOKEN_SHA256`. Set `LAD_PRIVATE_RECIPES_FILE` to the absolute path above. Deliver the raw token to the intended tester by a separate private channel, not GitHub or an app build setting.
4. Start `python3 server.py` as a service with `LAD_PORT=9823`. Proxy only the intended HTTPS hostname/path to `http://127.0.0.1:9823`; add rate limiting, request-size bounds, TLS renewal and access-log redaction at the proxy. Restrict `/healthz` to internal monitoring.
5. In the app's Recipes tab, open “Закрытая библиотека”, enter that HTTPS base URL and the raw token, and connect.

The initial bearer-token model is suitable only for a small private pilot. It is not a complete paid-membership system: add per-user identities, scoped entitlements, token rotation/revocation, audit trails, author permissions, and account recovery before selling access. Authorized users can always copy content that their device received; server authorization protects **access**, not absolute secrecy after delivery. Images are intentionally omitted from the private API until authenticated asset delivery and caching rules are designed.

Run the API tests locally with `python3 -m unittest discover -s api -p 'test_*.py' -v` from the repository root.
