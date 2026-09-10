# Deploy Chat Studio

## Requirements

- One Node 22+ process, persistent writable storage and an HTTPS domain.
- Kick and/or Twitch registered applications. Only configured providers can connect.
- Outbound HTTPS to both platforms and WSS to `eventsub.wss.twitch.tv:443`.
- Public access to the Kick webhook and OAuth callbacks through the same domain.

Copy `.env.example` to `.env`, fill provider keys and set `PUBLIC_URL` to the exact
HTTPS origin (no path, query, fragment or trailing slash). Register the URLs from
the README exactly. Kick cannot deliver webhooks to an unexposed localhost service;
use an HTTPS development tunnel for live tests.

Generate a private persistence key and append it to the local configuration:

```sh
node --input-type=module -e 'import {appendFileSync} from "node:fs"; import {randomBytes} from "node:crypto"; appendFileSync(".env", "\nSESSION_SECRET=" + randomBytes(32).toString("hex") + "\n");'
```

Keep this key stable and backed up securely. Losing it loses access to stored
sessions. Changing it without migrating the file fails startup rather than
silently discarding connections. Remove the empty example assignment if your
environment-file parser does not accept duplicate keys.

## Docker

```sh
docker compose up --build -d
```

The compose file exposes port 8787 on **127.0.0.1 only**. Terminate TLS in your
existing reverse proxy and forward the configured domain to `127.0.0.1:8787`.
Redirects and origin checks always use `PUBLIC_URL`; forwarded host values are
not trusted. The Docker volume retains encrypted sessions.

For a reverse proxy in another container, place it on the compose network and
forward to `chat:8787`. Keep the chat container off direct public HTTP. Disable
query-string and Authorization/Cookie header logging in the proxy, because OAuth
callbacks include authorization codes.

Apply request-size, connection and per-client rate limits at the edge. The app
also enforces a 64 KiB body limit, a 100-session cap and 20 session creations per
minute per direct peer address. Behind a reverse proxy the peer address is shared,
so the in-process limit acts as an aggregate fallback.

The image runs as the `node` user. Do not share its volume between replicas.
`GET /health` is a process check, not a guarantee of provider health. Monitor
connection failures and disk space as well.

## Direct Node hosting

Set `NODE_ENV=production`, `DATA_FILE=/your-private-data/sessions.enc`,
`SESSION_SECRET`, `PUBLIC_URL` and provider credentials in the host's secret
configuration. The directory must be writable only by the service account.
Run `node server/index.mjs` with a supervisor and HTTPS in front of it.

Sign-in uses an HttpOnly SameSite=Lax cookie with Secure enabled under HTTPS.
Streamers must return through the same browser used to start sign-in. Studio and
overlay use the same origin, but OBS uses a cookie-free read-only connection.
Keep overlay links private; replace a link if exposed.

## Live acceptance before release

1. Configure real Kick and Twitch apps. Connect two streamer accounts in separate
   browser profiles. Verify consent, callback and connected status.
2. Send a real viewer message. Confirm the username/content appears only in the
   correct studio and overlay. Include Unicode and a long message.
3. Add the copied URL to OBS Browser Source, 1920 × 1080. Place a game or image
   source behind it. Check transparent page background, panel opacity 0/35/100%,
   and fully visible text at every setting.
4. Change position, font size and Streamer Mode. Confirm OBS follows. Turning
   mode on again must not replay messages received while off.
5. Close the studio tab, keep OBS running and send another message.
6. On Twitch, delete a message, clear a user's messages and clear chat. Confirm
   the overlay follows. Kick moderation deletion is not yet implemented.
7. Restart Node with the same data file and secret. Confirm saved links/settings
   survive and reception resumes. No old chat should be restored.
8. Disconnect/reconnect the network. Check stale text is hidden and reception
   recovers. Revoke access and confirm actionable error feedback.
9. Replace the link: the old link must go blank. Disconnect: the active link must
   go blank too. To revoke the provider grant, also remove the app in platform
   account settings; Kick subscriptions may remain and be reused.
10. Record and inspect an actual OBS clip on the operating systems you will support.

Automated tests mock platform traffic. Real-account OAuth, delivery, rate limits,
token expiry during a full broadcast and OBS recording remain live release checks.
Do not advertise these as certified until completed.

## Commercial scope

This supplies a reusable service and self-service streamer interface. Payment
processing, subscriptions, customer entitlements, support tooling and a license
agreement are not included. Decide whether to sell managed access or self-hosted
installations before adding those features. Load-test the concurrency you plan to
sell; in-memory routing and encrypted snapshots target a small single instance.
