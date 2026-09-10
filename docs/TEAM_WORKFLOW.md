# Team workflow

The `twitch-chat` branch now contains the standalone Chat Studio product. Godot
scenes, addon scripts and the playable engine demo were removed from this branch
at the product owner's request. Other feature branches retain their history.

Do not merge this migration until the product owner asks. Do not force-push shared
branches. Review engine removal explicitly with the owners of `privacy-mask-copy`,
`stream-safe-audio` and `godot-sdk-foundation`: their Godot adapters cannot be wired
directly into a browser overlay.

## Modules

| Path | Responsibility |
| --- | --- |
| `public/` | Browser studio and transparent OBS overlay; literal message rendering |
| `server/app.mjs` | Session isolation, OAuth callbacks, settings and overlay endpoints |
| `server/providers/` | Official Kick and Twitch provider adapters |
| `server/storage.mjs` | Encrypted, single-process session persistence |
| `tests/` | Node built-in tests with mocked provider traffic |

Run `node --test tests/*.test.mjs` before pushing. Keep app keys in a local `.env`
or managed server secrets. Never commit credentials, runtime data, overlay links,
OAuth query strings, local screenshots or development fixtures.

Browser verification should include studio load, connection failure feedback,
opacity 0/35/100 with opaque text, each corner, mode off/on, reload persistence,
copy/open/replace link, disconnect, Unicode usernames, literal HTML-like chat text,
mobile layout and an isolated OBS browser context with no owner cookie.

Live release acceptance is documented in `DEPLOYMENT.md`. This migration does not
implement the other branches' privacy or audio features.
