# Keeply Omarchy Plugin

AI agent instructions for the Keeply Omarchy plugin.

## Architecture

```
keeply-omarchy/
├── manifest.json           # Plugin definition (bar-widget + service + overlay)
├── Panel.qml               # Bar icon + popup with search
├── Service.qml             # Auth state, API client, bookmark cache
├── Settings.qml            # Login/logout overlay
├── CredentialManager.qml   # secret-tool wrapper for token storage
├── AuthBridge.qml          # Python process lifecycle for OAuth
├── ResultRow.qml           # Bookmark search result row
├── ApiClient.js            # Pure JS: XMLHttpRequest API helpers
├── Model.js                # Pure JS: bookmark display logic
├── bin/keeply-auth         # Python OAuth helper (PKCE + local callback server)
└── tests/
```

## Key Components

- **Panel.qml**: Bar widget entry point. Shows Keeply bookmark icon in menu bar, popup with search field and result list.
- **Service.qml**: Session-wide singleton managing auth state, API calls, and bookmark data. Mounted once per session.
- **Settings.qml**: Overlay for login/logout UI.
- **CredentialManager.qml**: Wraps `secret-tool` for secure token storage in system keyring.
- **AuthBridge.qml**: Manages `bin/keeply-auth` Python process for OAuth PKCE flow.
- **ApiClient.js**: Pure JavaScript module for REST API calls to `https://api.keeply.tools`.
- **Model.js**: Pure JavaScript module for bookmark data transformation.

## Authentication Flow

1. User clicks "Connect" in Panel or Settings
2. AuthBridge starts `bin/keeply-auth` Python process
3. Python script generates PKCE pair, starts local HTTP server, opens browser
4. User authorizes in browser at `https://app.keeply.tools/oauth/authorize`
5. Browser redirects to `http://127.0.0.1:<port>/callback` with auth code
6. Python script exchanges code for token via `POST /oauth/token`
7. Python outputs `{"accessToken": "<token>"}` to stdout
8. AuthBridge passes token to Service
9. Service stores token via CredentialManager (secret-tool)
10. Service verifies token via `GET /users/me`

## API Endpoints

Base URL: `https://api.keeply.tools`

- `GET /users/me` - Verify token, get user info
- `GET /search?q=<query>&page=<n>&limit=<n>` - Full-text search
- `GET /bookmarks?page=<n>&limit=<n>&sort=<sort>` - List bookmarks
- `GET /folders` - List folders
- `GET /tags` - List tags
- `GET /bookmarks/sidebar-data` - Folder/tag counts

Auth header: `Authorization: ApiKey <token>`

## Coding Conventions

- Use `Style` and `Color` tokens, never hardcoded colors
- Every `Text` must set `textFormat: Text.PlainText` and an explicit `font.family`
- Icons are Nerd Font codepoints: `String.fromCodePoint(0xF02E)` (bookmark icon)
- Derive foreground/font from the bar: `bar ? bar.foreground : Color.foreground`
- JS modules use `.pragma library` for pure functions
- Python helper uses only stdlib (no pip dependencies)

## Verification

```bash
# Validate plugin structure
omarchy plugin validate .

# Run JS tests
node tests/test_*.js

# Run Python tests
python3 tests/test_*.py

# Run QML style checks
python3 tests/test_qml_style.py
```
