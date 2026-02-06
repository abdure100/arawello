---
summary: "VPS hosting hub for OpenClaw (Oracle/Fly/Hetzner/GCP/exe.dev)"
read_when:
  - You want to run the Gateway in the cloud
  - You need a quick map of VPS/hosting guides
title: "VPS Hosting"
---

# VPS hosting

This hub links to the supported VPS/hosting guides and explains how cloud
deployments work at a high level.

## Deploy Docker to your own server (script)

To move an existing Docker setup (e.g. from your Mac) to an Ubuntu server over SSH:

```bash
# From the repo root. Uses .openclaw-docker/ and .env from the repo.
SSH_HOST=<server-ip> SSH_KEY=/path/to/key.pem SSH_USER=ubuntu ./scripts/deploy-docker-to-server.sh
```

The script syncs the repo and config to the server, sets `gateway.bind` to `lan` so the gateway accepts external connections, writes a server `.env`, and runs `docker compose build` and `docker compose up -d`. First time on a fresh server, install Docker first (or run with `INSTALL_DOCKER=1`; you may need to log out and back in so the user is in the `docker` group).

- **Direct access**: open port 18789 in your cloud firewall, then open `http://<server-ip>:18789/` and paste the gateway token (from server `~/openclaw/.env` or `gateway.auth.token` in config).
- **SSH tunnel (recommended)**: do not open 18789 publicly; run `ssh -i key.pem -N -L 18789:127.0.0.1:18789 ubuntu@<server-ip>` and open `http://127.0.0.1:18789/`.

See [Docker](/install/docker) and [Remote access](/gateway/remote).

## Pick a provider

- **Railway** (one‑click + browser setup): [Railway](/railway)
- **Northflank** (one‑click + browser setup): [Northflank](/northflank)
- **Oracle Cloud (Always Free)**: [Oracle](/platforms/oracle) — $0/month (Always Free, ARM; capacity/signup can be finicky)
- **Fly.io**: [Fly.io](/platforms/fly)
- **Hetzner (Docker)**: [Hetzner](/platforms/hetzner)
- **GCP (Compute Engine)**: [GCP](/platforms/gcp)
- **exe.dev** (VM + HTTPS proxy): [exe.dev](/platforms/exe-dev)
- **AWS (EC2/Lightsail/free tier)**: works well too. Video guide:
  https://x.com/techfrenAJ/status/2014934471095812547

## How cloud setups work

- The **Gateway runs on the VPS** and owns state + workspace.
- You connect from your laptop/phone via the **Control UI** or **Tailscale/SSH**.
- Treat the VPS as the source of truth and **back up** the state + workspace.
- Secure default: keep the Gateway on loopback and access it via SSH tunnel or Tailscale Serve.
  If you bind to `lan`/`tailnet`, require `gateway.auth.token` or `gateway.auth.password`.

Remote access: [Gateway remote](/gateway/remote)  
Platforms hub: [Platforms](/platforms)

## Using nodes with a VPS

You can keep the Gateway in the cloud and pair **nodes** on your local devices
(Mac/iOS/Android/headless). Nodes provide local screen/camera/canvas and `system.run`
capabilities while the Gateway stays in the cloud.

Docs: [Nodes](/nodes), [Nodes CLI](/cli/nodes)
