# Error envelope fixtures

JSON samples of the server error envelope
(`Content-Type: application/vnd.stac.error+json`, `version` 1) and of the
recovery instruction it carries. They are the contract between a server and
this runtime: the runtime must accept them, and a server must produce
documents equivalent to them.

| File | Covers |
| --- | --- |
| `envelope_marker_version.json` | Minimal envelope: only `version`. |
| `envelope_recovery_full.json` | `recovery` with `key`, `recover` (list, with `recoveryOutcome`), `retry` (`overrides`, `removeHeaders`), `onFailure`, `onUnavailable`, `timeoutMs`. |
| `envelope_screen_only.json` | Envelope with a `screen` and nothing else. |
| `envelope_action_only.json` | Envelope with an `action` and nothing else. |
| `envelope_unknown_version.json` | Unsupported `version`: must be treated as a regular error. |

The recognition rule is: non-2xx status, `Content-Type` equal to
`application/vnd.stac.error+json` (parameters ignored), JSON object body and
an integer `version` equal to a supported one. Anything else is a regular error.

## Where the server repository consumes them

These files are the single source of truth. The server repository must not copy
them by hand and let them drift. Pick one of:

- a git submodule or a sparse checkout of
  `packages/stac/test/recovery/fixtures/` into the server repository, for
  example under `tests/fixtures/stac_error_envelope/`; or
- a CI step that downloads this directory at a pinned commit.

In the server tests, for each file `f`:

- `envelope_*` except `envelope_unknown_version.json`: build the same envelope
  with the server's own types and assert it serializes to JSON equal to `f`
  (compare parsed JSON, not bytes), and that its content type is
  `application/vnd.stac.error+json`.
- `envelope_unknown_version.json`: only assert that a client-side consumer
  would not recognize it; the server never emits it.

When the envelope contract changes, change the fixtures and the runtime test
`packages/stac/test/recovery/envelope_fixtures_test.dart` in the same commit,
then bump the pinned reference on the server side.
