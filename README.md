# dexter-server (Standalone Anisette v3 Server)

A completely self-contained, standalone **Anisette v3 & v1 Server** built for SideStore, AltStore, and iOS sideloading tools. Runs natively in Docker or cloud containers (Render, Railway, Fly.io, VPS) without depending on, proxying to, or relaying through any third-party servers.

---

## The -80045 & -80046 Fix (Lessons from altserver-macos27-anisette-fix)

Apple GrandSlam authentication strictly verifies three client attributes when authenticating Apple IDs and issuing Xcode developer signing tokens (`com.apple.gs.xcode.auth`):
1. **AuthKit Client Description (`X-MMe-Client-Info`)**
2. **User-Agent Header (`User-Agent`)**
3. **Routing Information Header (`X-Apple-I-MD-RINFO`)**

### Root Causes of Failures:
- **Error -80045 (Platform Conflict):** Previous standalone servers configured Windows PC descriptors (`<PC> <Windows;6.2...>`) while simultaneously sending a macOS Darwin kernel User-Agent (`akd/1.0 CFNetwork/... Darwin/22...`) alongside Android ADI routing info (`17106176` / `0x01050500`). When Apple's AuthKit inspects the request, this direct contradiction between OS profiles triggers instant rejection (-80045).
- **Error -80046 (Token Scope Rejection):** Apple explicitly rejects `com.apple.gs.xcode.auth` token requests if the client headers report Android or invalid device descriptions.

### The Fix in dexter-server:
`dexter-server` uses the verified, coherent Mac AuthKit profile from [altserver-macos27-anisette-fix](https://github.com/kimziro/altserver-macos27-anisette-fix) v1.3.3:
- **`client_info`**: `<MacBookPro13,3> <Mac OS X;10.12.6;16G29> <com.apple.AuthKit/1 (com.apple.akd/1.0)>`
- **`user_agent`**: `akd/1.0 CFNetwork/811.5.4 Darwin/16.7.0`
- **`routing_info`**: `16777216` (`0x01000000`, the genuine Mac ADI constant)
- Synchronized `v1Device.serverFriendlyDescription` and `X-MMe-Client-Info`.

All headers form a 100% coherent Apple AuthKit signature, completely eliminating -80045 and -80046.

---

## Features

- **100% Standalone:** Generates genuine Anisette tokens locally using the internal ADI engine. No proxy, no relay, no reliance on third-party servers.
- **Full Protocol Support:**
  - `GET /`: Anisette v1 backward compatibility.
  - `GET /health`: Lightweight health check for Render / Docker monitoring.
  - `GET /v3/client_info`: Returns matching Mac client info & user agent.
  - `POST /v3/get_headers`: Calculates OTP headers (`X-Apple-I-MD`, `X-Apple-I-MD-M`, `X-Apple-I-MD-RINFO`).
  - `GET /v3/provisioning_session`: Bi-directional WebSocket provisioning session.
- **Render Ready:**
  - Automatically respects Render's dynamic `PORT` environment variable.
  - Works with or without persistent disks.
  - Automatic HTTPS provided by Render.
- **Configurable Profiles:** Easily switch profiles or customize headers via environment variables.

---

## Deploying on Render (render.com)

1. **Create Web Service on Render:**
   - Go to [dashboard.render.com](https://dashboard.render.com) -> **New** -> **Web Service**.
   - Connect your GitHub repository (`dexter-server`).
   - Select **Docker** as the Runtime.
   - Instance Type: **Free** (or Starter).

2. **Environment Variables (Optional):**
   Render automatically assigns and manages `PORT`. You can optionally configure:
   | Variable | Default | Description |
   |---|---|---|
   | `ANISETTE_PROFILE` | `mac` | Profile preset (`mac`, `mac-xcode`, `windows`, `windows-akd`) |
   | `ANISETTE_CONFIG_DIR` | `~/.config/anisette-v3` | Path to store provisioning info (mount a Render disk here if you want persistence) |
   | `ANISETTE_CLIENT_INFO` | *(profile default)* | Custom Apple client info string |
   | `ANISETTE_USER_AGENT` | *(profile default)* | Custom User-Agent header |
   | `ANISETTE_ROUTING_INFO`| `16777216` | Custom routing info |

3. **Deploy:**
   - Click **Deploy Web Service**.
   - Your server will be available at: `https://your-service-name.onrender.com`

---

## Run with Docker / Podman Locally

```bash
docker run -d \
  --name dexter-server \
  --restart always \
  -p 6969:6969 \
  -v anisette-data:/home/Alcoholic/.config/anisette-v3 \
  ghcr.io/chandara/dexter-server:latest
```

---

## Client Setup (SideStore / AltStore)

1. Open **SideStore** on your iOS device.
2. Go to **Settings**:
   - Turn **On-Device Anisette** **OFF**.
   - Turn **Auto-Rotation** **OFF**.
   - Under **Anisette URL**, enter your Render URL:
     ```
     https://your-service-name.onrender.com
     ```
3. Tap **Reset adi.pb** in SideStore settings (clears old mismatched tokens).
4. Sign in with your Apple ID.
