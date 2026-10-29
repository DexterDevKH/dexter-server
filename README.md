# dexter-server (Anisette v3 macOS ADI Proxy)

High-performance, non-blocking **Anisette Reverse Proxy** built for SideStore, AltStore, and other sideloading tools.

Acts as a dedicated proxy routing requests through verified, genuine macOS ADI instances (such as `new.ani.sidestore.io`, `mac-ani.jkcoxson.com`, and `ani.iloader.app`), completely bypassing Apple's authentication blocks (**Errors -80045 and -80046**).

---

## Why Reverse Proxy? (Fixing -80045 & -80046)

Apple's GrandSlam authentication security rejects legacy anisette servers:
1. **Error -80046:** Requests using Android/Windows client headers or Android `libCoreADI.so` are rejected when requesting Xcode developer tokens (`com.apple.gs.xcode.auth`).
2. **Error -80045:** Spoofing macOS headers while generating tokens with Android's `libCoreADI.so` causes cryptographic signature mismatch during SRP initialization and Apple rejects the request.

**dexter-server** solves this permanently by proxying all provisioning sessions and header calculations to genuine macOS ADI backends while serving as your private, always-available endpoint.

---

## Features

- **Full Anisette V3 & V1 Support:**
  - `GET /`: Anisette v1 backward compatibility.
  - `GET /v3/client_info`: Relays genuine macOS Darwin user agent & client info (`<MacBookPro13,3>` + `Darwin/16.7.0`).
  - `POST /v3/get_headers`: Relays `adi_pb` and identifier to calculate genuine macOS OTP headers.
  - `GET /v3/provisioning_session`: Bidirectional, non-blocking WebSocket relay between SideStore and upstream macOS ADI.
- **Sticky Upstream Affinity:** Ensures `adi.pb` provisioned on a specific Mac machine is matched during `get_headers`, preventing `-45061` desync.
- **Automatic Multi-Server Failover:** If an upstream server is slow or down, `dexter-server` routes to the next healthy macOS backend:
  1. `https://new.ani.sidestore.io`
  2. `https://mac-ani.jkcoxson.com`
  3. `https://ani.jkcoxson.com`
  4. `https://ani.iloader.app`
  5. `https://ani3.stikstore.app`
  6. `https://ani2.stikstore.app`
- **Instant Container Startup:** No slow 80MB Apple Music APK downloads or fragile Android SO extraction.
- **Configurable Upstreams:** Point to your own Mac mini or custom backends via CLI (`--upstream`) or environment variable (`UPSTREAM_ANISETTE_URL`).

---

## Run with Docker / Podman

```bash
docker run -d \
  --name dexter-server \
  --restart always \
  -p 6969:6969 \
  ghcr.io/chandara/dexter-server:latest
```

### With Custom Upstream Server(s)

To prioritize your own upstream macOS server:

```bash
docker run -d \
  --name dexter-server \
  --restart always \
  -p 6969:6969 \
  -e UPSTREAM_ANISETTE_URL="https://new.ani.sidestore.io" \
  ghcr.io/chandara/dexter-server:latest
```

---

## Deploy with Ansible

Use `setup-anisette-v3-ansible.yaml` to deploy rootless with Podman and auto-update:

```bash
ansible-playbook -i inventory setup-anisette-v3-ansible.yaml -k
```

---

## SideStore Setup Instructions

1. Open **SideStore** on your iOS device.
2. Go to **Settings**:
   - Turn **On-Device Anisette** **OFF**.
   - Turn **Auto-Rotation** **OFF**.
   - Under **Anisette URL**, enter your server URL:
     ```
     http://<YOUR_SERVER_IP>:6969
     ```
3. Tap **Reset adi.pb** in SideStore settings (to flush any old mismatched tokens).
4. Sign in with your Apple ID.
