# The Math Academy web API

Math Academy has no public API. MathGate uses the same endpoints the website's own JavaScript
uses, with the same session cookies a browser would hold. Both apps implement this contract
independently — Kotlin in `android/`, Swift in `ios/` — so this file is the single description of
what they are both talking to.

Everything here was verified against a real account on 3 September 2026. If the gate starts
reporting "unexpected response", start here.

## Sign-in

```
POST https://www.mathacademy.com/login
Content-Type: application/x-www-form-urlencoded

usernameOrEmail=<user>&password=<password>&submit=LOGIN
```

There is no CSRF token and no captcha in the form.

| Outcome | Response |
|---|---|
| Success | `302` to a path that is not `/login` or `/session-expired`, plus both cookies |
| Wrong credentials | `302` back to `/login`, or `200` re-rendering the page with `<div id="errorMessage">` |

Success sets two cookies, both `Secure` and `HttpOnly`, both expiring 30 days out:

- `session` — base64 JSON. The payload records the user agent and an IP geolocation, so **every
  request must use the same `User-Agent`**, or the session can be invalidated. Both apps send one
  fixed desktop Chrome string.
- `session.sig` — the signature over it. Useless without the other half, but still credential
  material: never log or commit either value.

Whether the 30-day expiry slides on use is unknown, so both apps re-login proactively once the
cookie is within two days of expiring, and once more if a request comes back looking signed out.

## Completed tasks

```
GET https://www.mathacademy.com/api/previous-tasks/{cursor}
Accept: application/json, text/plain, */*
Referer: https://www.mathacademy.com/learn
Cookie: session=…; session.sig=…
```

`{cursor}` is a JavaScript `Date.toString()` value, URL-encoded the way `encodeURIComponent`
does it (`%20`, never `+`):

```
Thu Sep 04 2026 11:30:00 GMT-0800 (Pacific Standard Time)
```

Two things about it are load-bearing and neither is obvious:

- **The `GMT-0800 (Pacific Standard Time)` label is fixed**, whatever zone the caller is in. The
  date and time components are local wall-clock. This mirrors the community
  [mathacademy-stats](https://github.com/rahimnathwani/mathacademy-stats) extension, which is
  known to work.
- **Pass tomorrow's date**, not today's. The cursor is an upper bound.

There is a `minumum` query parameter — the misspelling is theirs — defaulting to 25. The website
omits it at the default, so both apps omit it too, making the request byte-for-byte the one a
logged-in browser makes.

### Response

A JSON array of the most recent tasks, newest first:

```json
[
  {
    "id": 1234567,
    "type": "Lesson",
    "points": 10,
    "pointsAwarded": 9,
    "progress": 100,
    "topic": { "name": "…", "course": { "name": "…" } },
    "started": "2026-09-03T13:52:11.000Z",
    "completed": "2026-09-03T14:05:08.000Z"
  }
]
```

Only three fields matter to the gate:

| Field | Use |
|---|---|
| `completed` | ISO 8601 UTC, or absent/null for an unfinished task. Counted when it is at or after the period start. |
| `pointsAwarded` | XP, shown to the user. Falls back to `points`. |
| `type` | Displayed only. **Every type counts** — Lesson, Review, Multistep, Quiz and anything new. |

Unknown fields are ignored and a malformed element is skipped. Only "the body is not a JSON
array" is treated as the API having changed, because that is the case where continuing would
mean guessing.

## Signed-out responses

A dead session shows up as a `3xx`, a `401`/`403`/`404`, or an HTML body where JSON was
expected. Any of those triggers exactly one re-login and one retry; still bad after that is
reported as an unexpected response, and the gate stays shut.

## Checking it by hand

`tools/ma_probe.sh` exercises both endpoints with curl and prints status codes, cookie names and
a task summary. It reads the password without echoing it and never prints it.
