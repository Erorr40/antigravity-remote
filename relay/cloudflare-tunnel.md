# Cloudflare Tunnel Setup Guide (Zero Port Forwarding)

Cloudflare Tunnel creates an encrypted outbound-only connection from your relay or laptop to Cloudflare's global edge network. No router ports need to be opened, and no static public IP is required.

## 1. Prerequisites
- Free Cloudflare account
- Domain managed on Cloudflare DNS (e.g. `yourdomain.com`)
- `cloudflared` CLI installed (`brew install cloudflared`, `winget install Cloudflare.cloudflared`, or `apt install cloudflared`)

---

## 2. Fast Setup (One-Command Quick Tunnel for Testing)

Run directly on the machine running `relay/server.js`:

```bash
cloudflared tunnel --url http://localhost:8765
```

Cloudflare generates a free public URL:
`https://random-subdomain.trycloudflare.com`

Your mobile app connects to:
`wss://random-subdomain.trycloudflare.com`

---

## 3. Production Named Tunnel with Custom Domain

### Step 1: Authenticate Cloudflare
```bash
cloudflared tunnel login
```

### Step 2: Create Named Tunnel
```bash
cloudflared tunnel create antigravity-relay
```
*Note Tunnel ID printed to terminal (e.g. `abcdef12-3456-7890-abcd-ef1234567890`).*

### Step 3: Configure Ingress Rules
Create `~/.cloudflared/config.yml`:

```yaml
tunnel: <YOUR-TUNNEL-ID>
credentials-file: ~/.cloudflared/<YOUR-TUNNEL-ID>.json

ingress:
  - hostname: relay.yourdomain.com
    service: http://localhost:8765
    originRequest:
      noTLSVerify: true
  - service: http_status:404
```

### Step 4: Route DNS
```bash
cloudflared tunnel route dns antigravity-relay relay.yourdomain.com
```

### Step 5: Run as System Service
```bash
# Windows (PowerShell as Admin)
cloudflared service install
Start-Service cloudflared

# Linux
sudo cloudflared service install
sudo systemctl enable --now cloudflared

# macOS
sudo cloudflared service install
```

### Step 6: Connect Laptop Daemon & Mobile
Mobile app and Laptop Daemon connect securely over TLS with zero open firewall ports:
`wss://relay.yourdomain.com`
