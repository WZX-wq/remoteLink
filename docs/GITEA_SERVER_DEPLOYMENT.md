# KQ Remote Link Gitea Server Deployment

This workflow deploys the private RustDesk OSS server components used by KQ
Remote Link:

- `hbbs`: ID/rendezvous service
- `hbbr`: relay service

## Required Gitea Secret

Create this repository secret in Gitea:

| Secret | Value |
| --- | --- |
| `KQ_DEPLOY_SSH_KEY` | Private SSH key allowed to deploy to the Linux server |

The matching public key must be in the target user's `~/.ssh/authorized_keys`.

## Required Server Setup

The target Linux server needs:

- Docker Engine
- Docker Compose plugin or `docker-compose`
- Inbound security-group/firewall rules:
  - TCP `21115-21119`
  - UDP `21116`

## Standard Gitea Deployment

The repository contains the standard files requested by operations:

- `.gitea/workflows/deploy.yml`
- `scripts/deploy/deploy.sh`

The workflow runs on the `linux:host` runner label and deploys directly on the
runner host. It uses:

| Variable | Value |
| --- | --- |
| Repository | `http://43.154.197.96/giteaadmin/KQromoteLink.git` |
| Deploy directory | `/www/wwwroot/KQromoteLink` |
| Public host | `43.154.197.96` |
| Required TCP ports | `21115-21119` |
| Required UDP ports | `21116` |

On push to `main` or `master`, the workflow validates the shell scripts and
compose file, runs `scripts/deploy/deploy.sh`, starts `hbbs`/`hbbr`, and fails
if required containers, listeners, or the public key are missing.

`hbbs` and `hbbr` are started with RustDesk's managed key mode (`-k _`). This is
required for private-server client packaging because the Windows client needs
the generated `hbbs` public key in its signed `custom.txt`.

If you want the client package to be built before the first server run,
pre-generate the hbbs/hbbr key pair:

```powershell
.\scripts\new-kq-server-key-pair.ps1
```

Then add the printed values to the runner environment or repository secrets.
For the current test server, `.gitea/workflows/deploy.yml` also embeds the
pre-generated test key pair directly so the runner can deploy even when the
Gitea Actions secrets API is unavailable.

| Variable | Value |
| --- | --- |
| `KQ_HBBS_PUBLIC_KEY` | Generated public key; also used as the client `ServerKey` |
| `KQ_HBBS_SECRET_KEY` | Generated secret key; keep private |

When both variables are present, the deploy script seeds
`/www/wwwroot/KQromoteLink/data/id_ed25519.pub` and `id_ed25519` before
starting `hbbs`/`hbbr`.

## Manual SSH Workflow

Open **Actions -> Deploy RustDesk Server -> Run workflow**, then fill:

| Input | Example |
| --- | --- |
| `host` | `remote.example.com` |
| `user` | `root` |
| `port` | `22` |
| `install_dir` | `/opt/kq-remote-link-server` |

The workflow uploads:

- `deploy/rustdesk-server.compose.yml`
- `deploy/deploy-rustdesk-server.sh`
- `deploy/export-hbbs-public-key.sh`
- `deploy/check-rustdesk-server.sh`

It then starts `hbbs` and `hbbr` on the server.

The workflow also runs `deploy/check-rustdesk-server.sh`, which prints:

- Docker Compose service status
- local listeners for ports `21115-21119`
- the `hbbs` public key
- recent `hbbs` / `hbbr` logs

The health check is intentionally strict. It fails the workflow if:

- `hbbs` or `hbbr` is not running
- `data/id_ed25519.pub` is missing or empty
- TCP listeners `21115`, `21116`, or `21117` are missing
- UDP listener `21116` is missing when listener tooling is available

## After Deployment

The workflow logs print the `hbbs` public key from:

```text
/www/wwwroot/KQromoteLink/data/id_ed25519.pub
```

If operations needs to recover the key from a running server manually, run:

```bash
cd /www/wwwroot/KQromoteLink
./incoming/export-hbbs-public-key.sh
```

Use that key when generating the private-server client package:

```powershell
.\scripts\new-kq-private-server-client-package.ps1 `
  -RendezvousServer "43.154.197.96:21116" `
  -RelayServer "43.154.197.96:21117" `
  -ServerKey "<hbbs public key>" `
  -PublicKey "<custom-client public key>" `
  -SecretKey "<custom-client secret key>" `
  -BuildClient
```

Then verify server connectivity from a client-side network:

```powershell
.\scripts\test-kq-server.ps1 `
  -RendezvousServer "43.154.197.96:21116" `
  -RelayServer "43.154.197.96:21117"
```

When operations sends back the `hbbs` public key, validate it before packaging:

```powershell
.\scripts\test-kq-server.ps1 `
  -RendezvousServer "43.154.197.96:21116" `
  -RelayServer "43.154.197.96:21117" `
  -ServerKey "<hbbs public key>"
```
