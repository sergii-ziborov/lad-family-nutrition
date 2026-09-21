# Private family and recipe API (pilot)

The iPhone app bundles public demo recipes. This API reads private recipes and the family profile from JSON files **outside this public repository**, and returns them only to a client with a high-entropy bearer token. The app stores the token in the device Keychain and caches family profiles locally. Server source code is public; family data, private recipes and credentials are not.

`GET /v1/recipes` and `GET /v1/family` require `Authorization: Bearer <token>`. They return objects matching [private-recipes.schema.json](private-recipes.schema.json) and [private-family.schema.json](private-family.schema.json), respectively. `GET /healthz` is unauthenticated for loopback monitoring only. All responses use `Cache-Control: no-store`. The server binds only to `127.0.0.1`; a separate HTTPS reverse proxy is required for an iPhone to connect. Never expose port 9823 directly to the internet.

To prepare a pilot instance:

1. Use a dedicated HTTPS hostname or a publicly trusted IP-address certificate. Do not reuse an unrelated production app's URL or credentials. Let's Encrypt IP certificates are short-lived (about six days): automate frequent renewal and reload the proxy only after a successful renewal.
2. Create a dedicated non-privileged service user and private data directory such as `/var/lib/lad`, readable only by that service user. Put `private-recipes.json` (initially `{"recipes":[]}`) and `private-family.json` there. Do not put either in Git, a public Docker image, or public screenshots.
3. Generate a random token with `openssl rand -hex 32`. Store the SHA-256 digest of the **trimmed** token, not the raw token, in `LAD_TOKEN_SHA256`; set `LAD_PRIVATE_RECIPES_FILE` and `LAD_PRIVATE_FAMILY_FILE` to absolute paths. Deliver the raw token privately, never through GitHub or an app build setting.
4. Start `python3 server.py` as a service with `LAD_PORT=9823`. Proxy only `/v1/recipes` and `/v1/family` to `http://127.0.0.1:9823`; add rate limiting, request-size bounds, TLS renewal and access-log redaction. Keep `/healthz` loopback-only.
5. In the app's Family or Recipes tab, open “Облако Лада”, enter the HTTPS base URL and key, and connect. The app imports names and ages; edits to goals, portions and restrictions remain local on the device.

The initial bearer-token model is suitable only for a small private pilot. It is not a complete paid-membership system: add per-user identities, scoped entitlements, token rotation/revocation, audit trails, author permissions, and account recovery before selling access. Authorized users can always copy content that their device received; server authorization protects **access**, not absolute secrecy after delivery. Images are intentionally omitted from the private API until authenticated asset delivery and caching rules are designed.

Run the API tests locally with `python3 -m unittest discover -s api -p 'test_*.py' -v` from the repository root.
