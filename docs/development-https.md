# Development HTTPS Setup

SPARC supports opt-in HTTPS in development using
[mkcert](https://github.com/FiloSottile/mkcert)-generated
certificates. This provides a production-like TLS experience
without browser certificate warnings.

---

## Prerequisites

**You must install [mkcert](https://github.com/FiloSottile/mkcert)
on your local machine before running `bin/setup-ssl`.** mkcert is
a standalone CLI tool that generates locally-trusted TLS
certificates — no new gem or npm dependencies are needed.

Choose the install method that matches your platform:

<!-- markdownlint-disable MD013 -->

| Platform | Method | Command |
| --- | --- | --- |
| macOS | Homebrew | `brew install mkcert` |
| macOS | MacPorts | `sudo port install mkcert` |
| macOS | Binary | Download from [GitHub Releases](https://github.com/FiloSottile/mkcert/releases) |
| Ubuntu / Debian | apt | `sudo apt install mkcert` |
| Linux | Binary | Download from [GitHub Releases](https://github.com/FiloSottile/mkcert/releases) |
| Windows | Chocolatey | `choco install mkcert` |
| Windows | Scoop | `scoop install mkcert` |

<!-- markdownlint-enable MD013 -->

**Manual / binary install** (any platform): download the binary
for your OS and architecture from the
[GitHub Releases](https://github.com/FiloSottile/mkcert/releases)
page, rename it to `mkcert`, make it executable
(`chmod +x mkcert`), and move it to a directory on your `PATH`
(e.g., `/usr/local/bin`).

Verify the installation:

```bash
mkcert --version
```

---

## One-Time Setup

```bash
bin/setup-ssl
```

This script:

1. Installs the mkcert local CA into your system trust store
2. Generates `ssl/localhost+2.pem` and `ssl/localhost+2-key.pem`
   covering `localhost`, `127.0.0.1`, and `::1`

The `ssl/` directory is git-ignored. Certificates are local to
your machine.

---

## Starting with HTTPS

### Local Rails Server

```bash
SSL_DEV=true bin/dev
```

Open **<https://localhost:3443>** in your browser.

HTTP remains available on port 3000 and automatically redirects
to HTTPS on 3443.

### Docker Compose

1. Run `bin/setup-ssl` on your **host** machine (certificates
   are volume-mounted into the container)
2. Add `SSL_DEV=true` to your `.env` file, or uncomment
   `SSL_DEV: "true"` in `docker-compose.yaml`
3. Start normally:

```bash
docker compose up
```

Open **<https://localhost:3443>**.

---

## Disabling HTTPS

Remove or unset `SSL_DEV`:

```bash
bin/dev                    # HTTP on port 3000 (default)
SSL_DEV=false bin/dev      # Explicit disable
```

---

## How It Works

- **Puma** conditionally binds an SSL listener on port 3443
  when `SSL_DEV=true` (see `config/puma.rb`)
- **Rails** enables `force_ssl` in development to redirect
  HTTP to HTTPS and set secure cookies
  (see `config/environments/development.rb`)
- HTTP on port 3000 remains available alongside HTTPS on 3443
- No new gem dependencies -- mkcert is a standalone CLI tool
- No HSTS headers in development (avoids caching issues when
  switching back to HTTP)

---

## Environment Variables

| Variable | Default | Description |
| --- | --- | --- |
| `SSL_DEV` | `false` | Enable HTTPS in development |
| `SSL_PORT` | `3443` | Override HTTPS port |

---

## Troubleshooting

### Browser still shows certificate warning

Run `mkcert -install` to ensure the local CA is trusted,
then restart your browser.

### Port 3443 already in use

Override with:

```bash
SSL_DEV=true SSL_PORT=3444 bin/dev
```

### Docker container cannot find certificates

Ensure you ran `bin/setup-ssl` on the **host** machine (not
inside the container). The `ssl/` directory is volume-mounted
read-only into the container.

### curl from inside Docker container shows cert error

This is expected. The mkcert CA is installed on the host, not
inside the container. Browser access from the host works fine.
For in-container testing, use `curl -k` (insecure) or install
the mkcert CA inside the container manually.

---

## Testing HTTPS Configuration

```bash
bundle exec rspec spec/config/https_enforcement_spec.rb
```
