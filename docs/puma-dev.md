# Local Development with puma-dev

Access SPARC at **`http://sparc.test`** instead of `http://localhost:3000`
using [puma-dev](https://github.com/puma/puma-dev) — a zero-config Puma
process manager for macOS that maps `.test` domains to local Rails apps.

---

## Why puma-dev?

- **Clean URLs** — `http://sparc.test` (no port numbers)
- **Auto-start** — Puma boots automatically on first request
- **Auto-stop** — idle apps shut down after 15 minutes
- **HTTPS included** — `https://sparc.test` works out of the box
- **No Homebrew required** — install directly from GitHub releases

---

## Install

### 1. Download the binary

```bash
# Detect architecture and download the matching release
ARCH=$(uname -m)
case "$ARCH" in
  arm64) SUFFIX="darwin-arm64" ;;
  *)     SUFFIX="darwin-amd64" ;;
esac

curl -sL -o /tmp/puma-dev.zip \
  "https://github.com/puma/puma-dev/releases/download/v0.18.3/puma-dev-0.18.3-${SUFFIX}.zip"

unzip -o /tmp/puma-dev.zip -d /tmp
mkdir -p ~/bin
mv /tmp/puma-dev ~/bin/
chmod +x ~/bin/puma-dev
rm /tmp/puma-dev.zip
```

Verify the install:

```bash
~/bin/puma-dev -V
# => Version: 0.18.3 (go1.20.1)
```

> **Note:** If `~/bin` is not on your `PATH`, add `export PATH="$HOME/bin:$PATH"`
> to your shell profile (`~/.zshrc` or `~/.bashrc`).

### 2. Configure DNS (one-time, requires sudo)

This creates a macOS resolver that routes all `.test` domains to
`127.0.0.1`:

```bash
sudo puma-dev -setup
```

### 3. Install the background agent (one-time)

This installs a launchd agent that listens on ports 80 and 443:

```bash
puma-dev -install
```

### 4. Link SPARC

```bash
mkdir -p ~/.puma-dev
ln -sf /path/to/sparc ~/.puma-dev/sparc
```

Replace `/path/to/sparc` with the absolute path to your clone (e.g.,
`~/GitHub/sparc`).

---

## Usage

Once linked, open your browser:

| URL | Protocol |
|-----|----------|
| `http://sparc.test` | HTTP |
| `https://sparc.test` | HTTPS (self-signed cert) |

No need to manually start `bin/rails server` — puma-dev launches Puma
automatically on the first request and stops it after 15 minutes of
inactivity.

### Restart the app

After pulling new code or changing environment variables:

```bash
touch ~/.puma-dev/sparc     # signals puma-dev to restart SPARC
```

Or restart all apps:

```bash
pkill -USR1 puma-dev
```

### View logs

```bash
tail -f ~/Library/Logs/puma-dev.log          # puma-dev daemon log
tail -f /path/to/sparc/log/development.log   # Rails app log
```

---

## Sidekiq / Background Jobs

puma-dev only manages the web server. If you need background job
processing (document imports, large catalog imports), start Sidekiq
separately:

```bash
cd /path/to/sparc
bundle exec sidekiq
```

---

## Uninstall

```bash
puma-dev -uninstall                       # remove launchd agent
sudo rm /etc/resolver/test                # remove DNS resolver
rm ~/bin/puma-dev                         # remove binary
rm -rf ~/.puma-dev                        # remove app symlinks
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `http://sparc.test` doesn't resolve | Run `sudo puma-dev -setup` and `puma-dev -install` |
| App doesn't start | Check `tail -f ~/Library/Logs/puma-dev.log` |
| Port 80/443 conflict | Stop any running web servers (nginx, Apache) |
| HTTPS cert warning | Expected — browser will ask to trust the self-signed cert on first visit |
| Changes not reflecting | Run `touch ~/.puma-dev/sparc` to restart |
