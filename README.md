# dexter-server (Anisette v3 macOS Reverse Proxy)

High-performance, non-blocking **Anisette Reverse Proxy** built for SideStore, AltStore, and other sideloading tools.

Acts as a dedicated proxy routing requests through verified macOS ADI instances (such as `new.ani.sidestore.io`, `mac-ani.jkcoxson.com`, and `ani.iloader.app`), completely bypassing Apple's recent authentication blocks (Errors **-80045** and **-80046**).

---

## Why Reverse Proxy? (Fixing -80045 & -80046)

On October 21, 2026, Apple updated GrandSlam authentication security:
1. **Error -80046:** Requests using Windows/Linux client headers are rejected when requesting developer tokens (`com.apple.gs.xcode.auth` / `apptokens`).
2. **Error -80045:** Spoofing macOS headers while generating tokens with Android's `libCoreADI.so` (the old method used by legacy anisette servers) causes cryptographic signature mismatch during SRP initialization.

**dexter-server** solves this permanently by proxying all provisioning sessions and header calculations to genuine macOS ADI backends while serving as your private, always-available endpoint.

---

## Features

- **Full Anisette V3 & V1 Support:**
  - `GET /`: Anisette v1 backward compatibility.
  - `GET /v3/client_info`: Relays genuine macOS Darwin user agent & client info.
  - `POST /v3/get_headers`: Relays `adi_pb` and identifier to calculate genuine macOS OTP headers.
  - `GET /v3/provisioning_session`: Bidirectional, non-blocking WebSocket relay between SideStore and upstream macOS ADI.
- **Automatic Multi-Server Failover:** If an upstream server is slow or down, `dexter-server` instantly routes to the next healthy macOS backend:
  1. `https://new.ani.sidestore.io`
  2. `https://mac-ani.jkcoxson.com`
  3. `https://ani.iloader.app`
  4. `https://ani3.stikstore.app`
  5. `https://ani.jkcoxson.com`
  6. `https://ani2.stikstore.app`
- **Instant Container Startup:** No slow 80MB Apple Music APK downloads or fragile Android SO extraction.
- **Configurable Upstreams:** Point to your own Mac mini or custom backends via CLI or environment variable.

---

## Run with Docker

```bash
docker run -d \
  --name dexter-server \
  --restart always \
  -p 6969:6969 \
  dadoum/anisette-v3-server:latest
```

### With Custom Upstream Server(s)

To prioritize your own upstream macOS server:

```bash
docker run -d \
  --name dexter-server \
  --restart always \
  -p 6969:6969 \
  -e UPSTREAM_ANISETTE_URL="https://mac-ani.jkcoxson.com,https://new.ani.sidestore.io" \
  dadoum/anisette-v3-server:latest
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
3. Tap **Reset adi.pb** in SideStore settings.
4. Sign in with your Apple ID.
