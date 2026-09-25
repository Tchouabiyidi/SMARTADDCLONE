# SMARTADS API

The API uses Express routes/controllers, Sequelize models, SQLite persistence, Gemini video review, and WebSockets for Android TV schedule synchronization.

## Setup

```sh
cp .env.example .env
npm install
npm start
```

Node.js 22.5 or newer and `ffprobe` on `PATH` are required. Set strong independent values for `JWT_SECRET` and `TV_DEVICE_SECRET`.

## Endpoint groups

- Authentication: `/api/auth`
- Billboards: `/api/billboards`
- Video review: `/api/videos`
- Bookings and mock payments: `/api/bookings`
- TV pairing, devices, schedules, events, and media: `/api/tv`
- TV WebSocket: `/api/tv/socket`
- Administration: `/api/admin`

TV calls use `Authorization: Device <token>` with a `deviceId` query parameter. Management calls use `Authorization: Bearer <token>`.

Pairing secrets expire after five minutes. Device tokens are returned only to the pairing TV and only their hashes are persisted. Schedule mutations are committed before socket snapshots are broadcast.
