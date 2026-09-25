# SMARTADS

SMARTADS is a Flutter billboard booking and Android TV playback application backed by an Express, Sequelize, and SQLite API. One Flutter codebase presents the advertiser/owner/admin interface on phones and the web, and a focused playback interface when Android reports the Leanback TV feature.

## Main flow

1. An owner creates a billboard.
2. SMARTADS is installed on Android TV and displays a temporary QR pairing code.
3. An owner or administrator scans the code and assigns the TV to a billboard.
4. An advertiser uploads a video, passes Gemini review, books a slot, and completes the simulated payment.
5. The TV receives schedule snapshots over WebSocket, downloads verified media to its local cache, and loops it until the scheduled end time.
6. Administrators can stop or extend confirmed advertisements. Changes are persisted before being broadcast to connected TVs.

When a TV loses connectivity, it continues its last synchronized schedule using cached media. A stop or extension made while the TV is offline takes effect when it reconnects.

## Run locally

```sh
cd BACKEND
cp .env.example .env
npm install
npm start
```

```sh
cd FRONTEND
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:3000
```

For a physical Android TV, `API_BASE_URL` must be an HTTPS address or a LAN address reachable by the TV; `localhost` points to the TV itself.

## TV playback targets

Use `--dart-define=TV_SIMULATION=true` to open the playback screen in a development build:

```sh
cd FRONTEND
flutter run -d chrome --dart-define=TV_SIMULATION=true
flutter run -d linux --dart-define=TV_SIMULATION=true
flutter run -d windows --dart-define=TV_SIMULATION=true
```

Each native Linux simulator launch clears its saved pairing, schedule, and downloaded media. It unpairs the saved device on the backend when possible, then opens a fresh pairing screen.

The browser simulator downloads and verifies each scheduled video, then plays it from a temporary browser URL. Browser media is held in memory for the current session, so an offline browser cannot restore the video after a reload. Playback is muted in the browser to allow scheduled autoplay.

Linux desktop playback uses MPV. On Ubuntu or Debian, install its development and runtime packages before building:

```sh
sudo apt install libmpv-dev mpv libepoxy-dev
```

Windows playback requires the Flutter Windows desktop toolchain. The Android TV target continues to use the TV device's native video player.

## Backend structure

```text
BACKEND/src/
  config/       Sequelize connection and schema initialization
  models/       Sequelize models and associations
  controllers/  HTTP workflows
  routes/       Express routes
  middleware/   authentication, CORS, and errors
  services/     Gemini, booking rules, pairing, sockets, and media
  utils/        passwords, tokens, time, and HTTP errors
```

Payment is simulated; no money is transferred and the submitted phone number is not retained.
