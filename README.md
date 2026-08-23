# Keeply for Omarchy

Search and browse your [Keeply](https://keeply.tools) bookmarks from the [Omarchy](https://omarchy.dev) menu bar.

## Features

- **Quick search**: Type to search your bookmarks with full-text search
- **Recent bookmarks**: See your latest bookmarks when opening the popup
- **One-click open**: Click any bookmark to open it in your default browser
- **Secure**: OAuth authentication with PKCE, tokens stored in system keyring

## Installation

```bash
omarchy plugin add https://github.com/Keeply-link/keeply-omarchy.git --enable
```

Or for local development:

```bash
git clone https://github.com/Keeply-link/keeply-omarchy.git
cd keeply-omarchy
ln -sfn "$PWD" ~/.config/omarchy/plugins/io.github.rolfkoenders.keeply
omarchy restart shell
omarchy plugin enable io.github.rolfkoenders.keeply
```

## Setup

1. Click the Keeply icon (bookmark icon) in your menu bar
2. Click "Connect" to start the OAuth flow
3. Sign in to Keeply in your browser and authorize the plugin
4. You're connected! Start searching your bookmarks

## Usage

- **Search**: Type in the search field to find bookmarks
- **Open**: Click a bookmark to open it in your browser
- **Settings**: Click the gear icon to access login/logout
- **Keyboard**: Arrow keys to navigate, Enter to open, Escape to close

## Requirements

- [Omarchy](https://omarchy.dev) (Quattro or later)
- Python 3 (for OAuth flow)
- A Keeply account (free)

## Privacy

- Authentication is handled via OAuth with PKCE
- Your access token is stored securely in the system keyring (via `secret-tool`)
- Your token is never stored in config files or logs
- All API calls go directly to `https://api.keeply.tools`

## License

MIT
