# dexter-server (Standalone Anisette v3 Server)

A completely self-contained, standalone **Anisette v3 & v1 Server** built for SideStore, AltStore, and iOS sideloading tools. Runs natively in Docker or cloud containers (Render, Railway, Fly.io, VPS) without depending on, proxying to, or relaying through third-party servers.

---

## Why Error -80045 Happens and How It Is Fixed

Apple's GrandSlam authentication system validates the SRP cryptographic handshake and device headers:
1. **The Mac-Spoof Block on Linux/Docker:** In mid-October 2026, Apple began detecting and blocking Linux/Docker instances declaring Mac hardware descriptors (`<MacBookPro...>` / `Darwin`), returning **Error `-80045`**.
2. **The Verified Windows Profile:** AltStore PR #1834, iloader 2.3.8, and community research identified the only profile accepted by Apple GrandSlam on non-Mac servers:
   - **Client Info:** `<PC> <Windows;6.2(0,0);9200> <com.apple.AuthKit/1 (com.apple.iTunes/12.12.4.1)>`
   - **User Agent:** `akd/1.0 CFNetwork/808.1.4`
   - **Routing Info (`X-Apple-I-MD-RINFO`):** `33883392` (`0x02050500`, Windows ADI)
3. **`X-Apple-I-MD-LU` Base64 Formatting:** Genuine AuthKit expects `X-Apple-I-MD-LU` to be a Base64-encoded representation of the unique device identifier UUID, with TimeZone set to `"GMT"`.
4. **Cached Device State (`adi.pb`):** When authentication fails once, the client app (SideStore / AltStore) caches the failed `adi.pb` locally. **You must reset `adi.pb` in SideStore settings** so the app provisions a fresh identity.

---

## Features

- **100% Standalone:** Generates genuine Anisette tokens locally using the internal ADI engine. No proxy, no relay, no reliance on third-party servers.
- **Windows ADI Profile as Default:** Pre-configured with the verified Windows profile (`33883392`) to permanently bypass `-80045`.
- **Full Protocol Support:**
  - `GET /`: Anisette v1 backward compatibility.
  - `GET /health`: Lightweight health check for Render / Docker monitoring.
  - `GET /v3/client_info`: Returns matching client info & user agent.
  - `POST /v3/get_headers`: Calculates OTP headers (`X-Apple-I-MD`, `X-Apple-I-MD-M`, `X-Apple-I-MD-RINFO`, `X-Apple-I-MD-LU`).
  - `GET /v3/provisioning_session`: Bi-directional WebSocket provisioning session.
- **Render Ready:**
  - Automatically respects Render's dynamic `PORT` environment variable.
  - Works with or without persistent disks.
  - Automatic HTTPS provided by Render.

---

## Deploying on Render (render.com)

1. **Push Changes to GitHub:**
   ```bash
   git add .
   git commit -m "Fix -80045 with Windows ADI profile and Base64 LU"
   git push origin main
   ```

2. **Create Web Service on Render:**
   - Go to [dashboard.render.com](https://dashboard.render.com) -> **New** -> **Web Service**.
   - Connect your GitHub repository (`dexter-server`).
   - Select **Docker** as the Runtime.
   - Instance Type: **Free** (or Starter).

3. **Environment Variables (Optional):**
   | Variable | Default | Description |
   |---|---|---|
   | `ANISETTE_PROFILE` | `windows` | Profile preset (`windows`, `windows-itunes`, `mac`, `mac-xcode`) |
   | `ANISETTE_CONFIG_DIR` | `~/.config/anisette-v3` | Path to store provisioning info |
   | `ANISETTE_CLIENT_INFO` | *(profile default)* | Custom Apple client info string |
   | `ANISETTE_USER_AGENT` | *(profile default)* | Custom User-Agent header |
   | `ANISETTE_ROUTING_INFO`| `33883392` | Custom routing info |

4. **Deploy:**
   - Click **Deploy Web Service**.
   - Your server will be live at: `https://your-service-name.onrender.com`

---

## Crucial Client Step: How to Avoid -80045 in SideStore

If your device previously encountered `-80045`, SideStore has the old rejected token cached in memory. Follow these exact steps:

1. Open **SideStore** on your iPhone / iPad.
2. Go to **Settings**:
   - Turn **On-Device Anisette** **OFF**.
   - Turn **Auto-Rotation** **OFF**.
   - Under **Anisette URL**, enter your Render URL:
     ```
     https://your-service-name.onrender.com
     ```
3. Tap **Reset adi.pb** in SideStore settings (**CRITICAL STEP: this flushes the old rejected token**).
4. Force close SideStore and re-open it.
5. Sign in with your Apple ID.
