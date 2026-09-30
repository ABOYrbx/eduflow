# API reference (`/api/v1`)

Base URL (real): `http://127.0.0.1:3000/api/v1` — demo: `http://127.0.0.1:3100/api/v1`. Normative route list: `GET /api/v1/openapi.json`.

## Conventions

- **Auth**: `Authorization: Bearer <token>` on everything except `health`, `openapi.json`, `auth/login`, `auth/2fa`. Any `401` → back to login.
- **Lists**: `{items, total, limit, offset}` (`limit` default 50, max 200).
- **Errors**: `{error, code}`. Canonical codes: `VALIDATION` (400), `TOKEN_INVALID` / `TOKEN_EXPIRED` / `PENDING_INVALID` / `INVALID_CODE` / `BAD_CREDENTIALS` (401), `EDUPAGE_2FA` (401, re-login), `CAPTCHA_REQUIRED` (403), `NOT_FOUND` (404), `RATE_LIMITED` (429, >20 hits/10 min/IP on login+2FA), `CONFIG_MISSING` (503, e.g. no weather key), `UPSTREAM` (502).
- All `POST`/`PUT` return `200`.

## System (no auth)

| Method | Path | Returns |
|---|---|---|
| `GET` | `/health` | `{status:"ok",version:"v1"}` |
| `GET` | `/openapi.json` | Static OpenAPI 3.0 stub |

## Auth & account

| Method | Path | Body / params | Returns |
|---|---|---|---|
| `POST` | `/auth/login` | `{username, password, subdomain?, device?}` (`subdomain` defaults `login1`, demo `demo`) | `ok` → token set, or `2fa_required` + `pending_token` (TTL 10 min) |
| `POST` | `/auth/2fa` | `{pending_token, code}` (demo code `123456`) | Full token set, pending is single-use |
| `POST` | `/auth/logout` | — (Bearer) | `{status:"ok"}`, revokes current token |
| `POST` | `/auth/refresh` | `{refresh_token?}` or Bearer | Rotates the token, revokes the old one |
| `GET` | `/me` | — (Bearer) | `{subdomain, username}` |
| `GET` | `/devices` | — (Bearer) | `{items, total}` |
| `POST` | `/devices` | `{device?}` (Bearer) | Extra token for a named device |
| `DELETE` | `/devices/:id` | — (Bearer) | `{status:"ok"}` or `404 NOT_FOUND` |

Demo logins (fake provider only): `demo`/`demo` for instant access, `demo-2fa`/`demo` + code `123456` for the 2FA path.

## Messages

| Method | Path | Query / body | Notes |
|---|---|---|---|
| `GET` | `/messages` | `?since=YYYY-MM-DD`, `?type=sprava\|news\|anketa\|chat\|genotif`, `?q=`, `?refresh=1`, `limit/offset` | List envelope |
| `GET` | `/messages/:id/thread` | `?refresh=1` | `{likes, replies, reply_ids, summary, cached}` |
| `POST` | `/messages/read` | — | `{marked: n}` |
| `GET` | `/recipients` | `limit/offset` | List envelope |
| `POST` | `/messages/send` | `{recipients: string[]\|"a,b", body}` (`body` ≤ 5000) | New message |
| `POST` | `/messages/:id/reply` | `{body}` (≤ 5000) | Fresh thread |
| `POST` | `/messages/download-token` | `{event_id, idx}` | `{download_token, expires_in: 300}` |
| `GET` | `/messages/:id/attachments/:idx` | Bearer **or** `?dl=<token>` (recommended, 5 min) / `?token=` | Binary download |

## Homework, timetable, school day

| Method | Path | Query / body | Notes |
|---|---|---|---|
| `GET` | `/homework` | `?since=`, `?status=alle\|offen\|überfällig\|erledigt\|papierkorb` (default `alle`), `?include_tests=0/1`, `?q=`, `?refresh=`, `limit/offset` | `{items,total,limit,offset,counts,cache_info}` |
| `POST` | `/homework/:id/done` | `{done?: bool}` (tolerant `1/true/on/yes/ja`) | Updated task |
| `POST` | `/homework/:id/trash` | `{hide\|trash?: bool}` | Updated task |
| `GET` | `/timetable/day` | `?day=YYYY-MM-DD` (default today), `?refresh=1` | `{day, day_label, prev_day, next_day, today, lessons, cache_info}` |
| `GET` | `/timetable/week` | `?day=` (any date in the week, Mon–Fri derived) | `{day, monday, week_label, days[5], cache_info}` |
| `GET` | `/substitutions/week` | `?day=` | `{monday, week_label, days[{date, day_label, changes}]}` |
| `GET` | `/school/agenda` | `?since=` (default −30 d), `?until=` (default +60 d, max span 366 d), `?refresh=1` | `{items, total, since, until, cache_info}`; `kind = event\|exam\|attendance` |
| `GET` | `/grades` | `?refresh=1`, `limit/offset` | List envelope + `cache_info` |

## Weather, settings, cache

| Method | Path | Query / body | Notes |
|---|---|---|---|
| `GET` | `/wetter` | `?lat=&lon=` or `?city=` (≤ 100 chars) | `400` if neither; `503 CONFIG_MISSING` without key |
| `GET` | `/wetter/suche` | `?q=` (≥ 2 chars) | `{items: [{name, country, lat, lon}]}` |
| `GET` | `/settings` | — | `{schema: [...], values: {...}}` (`landing`, `hw_status`, `hw_tests`, `ov_unread`, `ov_homework`, `ov_order`, `ov_wetter`, `wetter_city`) |
| `PUT` | `/settings` | JSON object, merged over current values | `{status:"ok", values}` |
| `POST` | `/cache-clear` | — | `{status:"ok", cleared: n}` (keeps settings) |

## Examples

```sh
BASE=http://127.0.0.1:3100/api/v1   # demo

curl -s $BASE/health

TOKEN=$(curl -s -X POST $BASE/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"demo","password":"demo"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')

curl -s "$BASE/homework?status=offen&limit=5" -H "Authorization: Bearer $TOKEN"

# 2FA variant
PENDING=$(curl -s -X POST $BASE/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"demo-2fa","password":"demo"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["pending_token"])')
curl -s -X POST $BASE/auth/2fa \
  -H 'Content-Type: application/json' \
  -d "{\"pending_token\":\"$PENDING\",\"code\":\"123456\"}"
```
