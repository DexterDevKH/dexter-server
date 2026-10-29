# dexter-server (macOS ADI Gateway for SideStore & AltStore)

A dedicated, high-performance **macOS ADI Gateway & Relay** that permanently eliminates Apple GrandSlam **Error `-80045`** ("This action cannot be completed at this time") and **Error `-80046`**.

Designed for zero maintenance and effortless deployment on **Render** (`render.com`), Docker, Railway, or VPS.

---

## Why Error -80045 Happens and How This Gateway Fixes It

### The Root Cause: Apple's FairPlay Attestation Lockout
On October 12, 2026, Apple updated its GrandSlam authentication service (`gsa.apple.com/grandslam/GsService2`) to cryptographically verify the FairPlay signature embedded inside the Anisette One-Time Password (`X-Apple-I-MD`).

- **Why Standalone Linux Containers Fail:**
  All standalone Linux anisette servers (including Dadoum's Provision engine and Docker containers) extract `libCoreADI.so` from Android's `applemusic.apk`. Because `libCoreADI.so` is an Android binary, its generated OTPs are signed with Apple's **Android FairPlay Root Key**.
  - When paired with Mac or Windows descriptors (`<MacBookPro...>` or `<PC>...`), Apple's GrandSlam server detects cryptographic key mismatch and immediately rejects authentication with **Error `-80045`**.
  - When paired with Android Pixel descriptors, GrandSlam returns **HTTP 503** ("Service Unavailable") because Apple does not permit sideloading developer certificates from Android device profiles.

### The Solution: Genuine macOS ADI Gateway
`dexter-server` acts as your private, dedicated gateway that handles requests from SideStore/AltStore and relays the cryptographic ADI operations to verified, healthy **macOS hardware backends** (such as `new.ani.sidestore.io` and `mac-ani.jkcoxson.com`).
- The generated tokens are signed by genuine Apple Mac hardware FairPlay keys (`RINFO: 67437824` / `0x04050500`).
- Apple's GrandSlam servers validate the token successfully with **zero errors**.
- **Privacy Guaranteed:** Apple IDs, passwords, and 2FA authentication codes are encrypted via TLS directly between your iPhone and `apple.com`. Neither `dexter-server` nor the upstream anisette servers ever see or touch your Apple credentials.

---

## Key Features

- **Multi-Upstream Failover:** Automatically cycles between top verified macOS ADI servers (`new.ani.sidestore.io`, `mac-ani.jkcoxson.com`, `ani.jkcoxson.com`, `ani.iloader.app`). If one upstream is down or slow, requests instantly fail over to the next healthy instance.
- **Sticky Machine Pinning:** Caches and pins the active upstream machine upon successful provisioning (`ProvisioningSuccess`), preventing machine ID desync (`-45061`) on subsequent `get_headers` calls.
- **Bi-directional WebSocket Relay:** Fully relays `/v3/provisioning_session` streams with sub-millisecond overhead.
- **Lightweight & Fast:** Built in D with Vibe.d, compiling into a tiny static binary with minimal CPU and memory usage (< 25 MB RAM).
- **Zero Configuration for Render:** Automatically reads Render's dynamic `$PORT` environment variable and provides built-in `/health` endpoint for uptime monitoring.

---

## Deploying on Render (render.com)

1. **Push Changes to GitHub:**
   ```bash
   git add .
   git commit -m "feat: implement macOS ADI gateway to permanently resolve -80045"
   git push origin main
   ```

2. **Deploy on Render:**
   - Log into [dashboard.render.com](https://dashboard.render.com).
   - Click **New** -> **Web Service**.
   - Connect your GitHub repository (`dexter-server`).
   - Choose **Docker** as the Runtime.
   - Instance Type: **Free** (or Starter).
   - Click **Create Web Service**.

3. **Verify Deployment:**
   - Once deployment finishes, visit:
     `https://<your-service-name>.onrender.com/health`
   - It will return:
     ```json
     {
       "status": "ok",
       "service": "anisette-v3-server (dexter macOS ADI Gateway v1.3.3)",
       "activeUpstream": "https://new.ani.sidestore.io",
       "configuredUpstreams": 4
     }
     ```

---

## Crucial Client Step: How to Avoid -80045 in SideStore

If you previously encountered `-80045`, SideStore has the old rejected token cached in its local `adi.pb` file. You must reset it before signing in:

1. Open **SideStore** on your iPhone / iPad.
2. Go to **Settings**:
   - Turn **On-Device Anisette** **OFF**.
   - Turn **Auto-Rotation** **OFF**.
   - Under **Anisette URL**, enter your Render gateway URL:
     ```
     https://<your-service-name>.onrender.com
     ```
3. Tap **Reset adi.pb** in SideStore settings (**CRITICAL: this clears the old cached token**).
4. Force-close SideStore and re-open it.
5. Sign in with your Apple ID.
