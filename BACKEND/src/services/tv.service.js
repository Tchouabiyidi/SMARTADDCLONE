'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const { Op } = require('sequelize');
const { WebSocketServer, WebSocket } = require('ws');
const {
  sequelize, AppState, Billboard, Booking, TvDevice, TvPairingSession,
  TvPlaybackEvent, User, VideoReview,
} = require('../models');
const { fail } = require('../utils/errors');
const { timezone, zonedParts, wallClockToEpoch } = require('../utils/time');

const PAIRING_TTL_MS = 5 * 60 * 1000;
const DEVICE_STALE_MS = 90 * 1000;
const tokenHash = (value) => crypto.createHash('sha256').update(String(value)).digest('hex');
const secureEqual = (left, right) => {
  const a = Buffer.from(String(left)); const b = Buffer.from(String(right));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
};

class TvService {
  constructor() {
    this.clients = new Map();
    this.wss = null;
    this.deviceSecret = process.env.TV_DEVICE_SECRET || process.env.JWT_SECRET || 'smartads-local-demo-secret-change-me';
  }

  async revision() {
    return Number((await AppState.findByPk('tv_schedule_revision'))?.value || 0);
  }

  async nextRevision(transaction) {
    const state = await AppState.findByPk('tv_schedule_revision', { transaction });
    const value = Number(state?.value || 0) + 1;
    await AppState.upsert({ key: 'tv_schedule_revision', value: String(value) }, { transaction });
    return value;
  }

  deriveToken(deviceId, pairingSecret) {
    return crypto.createHmac('sha256', this.deviceSecret).update(`tv-device\n${deviceId}\n${pairingSecret}`).digest('base64url');
  }

  async startPairing({ deviceName, installationId, hardwareId, metadata, latitude, longitude, locationAccuracy }) {
    const installation = String(installationId || '').trim();
    if (installation.length < 20 || installation.length > 200) throw fail(400, 'This TV did not provide a valid installation identity.');
    const hardwareHash = hardwareId ? tokenHash(String(hardwareId)) : null;
    const identityWhere = [{ installation_id: installation }];
    if (hardwareHash) identityWhere.push({ hardware_hash: hardwareHash });
    const registered = await TvDevice.findOne({ where: { [Op.or]: identityWhere, status: 'active' } });
    if (registered) throw fail(409, 'This television is already registered. Ask an administrator to disconnect it before pairing again.');
    await TvPairingSession.update(
      { status: 'expired' },
      { where: { installation_id: installation, status: 'pending' } },
    );
    const numericLatitude = Number(latitude);
    const numericLongitude = Number(longitude);
    const numericAccuracy = Number(locationAccuracy);
    const secret = crypto.randomBytes(32).toString('base64url');
    const session = await TvPairingSession.create({
      secret_hash: tokenHash(secret),
      user_code: crypto.randomBytes(4).toString('hex').toUpperCase(),
      device_name: String(deviceName || 'SMARTADS TV').trim().slice(0, 80) || 'SMARTADS TV',
      installation_id: installation,
      hardware_hash: hardwareHash,
      device_metadata: JSON.stringify(metadata && typeof metadata === 'object' ? metadata : {}).slice(0, 4000),
      latitude: Number.isFinite(numericLatitude) && numericLatitude >= -90 && numericLatitude <= 90 ? numericLatitude : null,
      longitude: Number.isFinite(numericLongitude) && numericLongitude >= -180 && numericLongitude <= 180 ? numericLongitude : null,
      location_accuracy: Number.isFinite(numericAccuracy) && numericAccuracy >= 0 ? numericAccuracy : null,
      status: 'pending',
      expires_at: new Date(Date.now() + PAIRING_TTL_MS),
      created_at: new Date(),
    });
    return {
      pairingId: session.id,
      secret,
      userCode: session.user_code,
      qrData: `smartads://pair?session=${encodeURIComponent(session.id)}&secret=${encodeURIComponent(secret)}&code=${session.user_code}`,
      expiresAt: session.expires_at,
    };
  }

  async pairingSession(id, secret) {
    const session = await TvPairingSession.findByPk(id);
    if (!session || !secureEqual(session.secret_hash, tokenHash(secret))) throw fail(404, 'Pairing session not found.');
    if (session.status === 'pending' && new Date(session.expires_at).getTime() < Date.now()) {
      session.status = 'expired';
      await session.save();
    }
    return session;
  }

  async lookupByUserCode(userCode) {
    const code = String(userCode || '').trim().toUpperCase();
    if (!code) throw fail(400, 'Enter the code shown on the TV screen.');
    const session = await TvPairingSession.findOne({ where: { user_code: code, status: 'pending' } });
    if (!session) throw fail(404, 'No pending TV found with that code. Make sure the TV is on the pairing screen.');
    if (new Date(session.expires_at).getTime() < Date.now()) {
      await session.update({ status: 'expired' });
      throw fail(410, 'This pairing code has expired. Restart the TV to get a new one.');
    }
    // Return session id + a masked secret — the caller still needs to supply their
    // own secret from the QR URL. For code-only lookup we return the session info
    // so the frontend can present the billboard picker; actual approval still
    // requires the secret which is embedded in the QR data but we expose a
    // code-based approval path below.
    return { sessionId: session.id, userCode: session.user_code, deviceName: session.device_name, expiresAt: session.expires_at };
  }

  async pairingStatus(id, secret) {
    const session = await this.pairingSession(id, secret);
    if (session.status !== 'approved') return { status: session.status, expiresAt: session.expires_at };
    const device = await TvDevice.findByPk(session.device_id, { include: [{ model: Billboard, as: 'billboard' }] });
    if (!device) throw fail(410, 'The paired TV no longer exists.');
    const token = this.deriveToken(device.id, secret);
    if (!device.token_hash) {
      device.token_hash = tokenHash(token);
      await device.save();
    }
    return {
      status: 'approved', token, timezone,
      device: { id: device.id, name: device.name, billboardId: device.billboard_id, billboardName: device.billboard.name },
    };
  }

  async approvePairing(user, id, body) {
    // For code-only pairing (no secret in body): look up by user_code instead
    let session;
    if (body.userCode && !body.secret) {
      const code = String(body.userCode).trim().toUpperCase();
      session = await TvPairingSession.findOne({ where: { user_code: code, status: 'pending' } });
      if (!session) throw fail(404, 'No pending TV found with that code.');
      if (new Date(session.expires_at).getTime() < Date.now()) {
        await session.update({ status: 'expired' });
        throw fail(410, 'This pairing code has expired. Restart the TV to get a new code.');
      }
    } else {
      session = await this.pairingSession(id, String(body.secret || ''));
    }
    if (session.status !== 'pending') throw fail(409, `This pairing session is ${session.status}.`);

    let billboard;
    if (user.role === 'admin') {
      billboard = await Billboard.findOne({ where: { id: body.billboardId } });
    } else if (user.role === 'owner') {
      billboard = await Billboard.findOne({ where: { id: body.billboardId, owner_id: user.id } });
    } else if (user.role === 'advertiser') {
      // Advertisers can pair a billboard where they have a confirmed booking
      const booking = await Booking.findOne({
        where: { advertiser_id: user.id, billboard_id: body.billboardId, status: 'confirmed' },
      });
      if (!booking) throw fail(403, 'You can only pair a TV to a billboard where you have a confirmed booking.');
      billboard = await Billboard.findByPk(body.billboardId);
    } else {
      throw fail(403, 'You do not have permission to pair TVs.');
    }
    if (!billboard) throw fail(404, 'Billboard not found or not accessible by this account.');

    const device = await sequelize.transaction(async (transaction) => {
      const identityWhere = [{ installation_id: session.installation_id }];
      if (session.hardware_hash) identityWhere.push({ hardware_hash: session.hardware_hash });
      let created = await TvDevice.findOne({ where: { [Op.or]: identityWhere }, transaction });
      const values = {
        owner_id: billboard.owner_id, billboard_id: billboard.id, name: session.device_name,
        installation_id: session.installation_id, hardware_hash: session.hardware_hash,
        device_metadata: session.device_metadata, latitude: session.latitude, longitude: session.longitude,
        location_accuracy: session.location_accuracy, token_hash: '', status: 'active', paired_at: new Date(),
      };
      if (created) await created.update(values, { transaction });
      else created = await TvDevice.create({ ...values, created_at: new Date() }, { transaction });
      await session.update({ status: 'approved', billboard_id: billboard.id, approved_by: user.id, device_id: created.id }, { transaction });
      return created;
    });
    return { message: 'TV paired successfully.', deviceId: device.id, userCode: session.user_code };
  }

  async authenticate(deviceId, token) {
    const device = await TvDevice.findByPk(String(deviceId || ''), { include: [{ model: Billboard, as: 'billboard' }] });
    if (!device || device.status !== 'active' || !device.token_hash || !secureEqual(device.token_hash, tokenHash(token))) {
      throw fail(401, 'Invalid or revoked TV credential.');
    }
    return device;
  }

  async authenticateRequest(req) {
    const raw = String(req.headers.authorization || '');
    return this.authenticate(req.query.deviceId, raw.startsWith('Device ') ? raw.slice(7) : '');
  }

  async checksum(review) {
    if (review.sha256 && review.file_size) return { sha256: review.sha256, size: review.file_size };
    const data = await fs.promises.readFile(review.file_path);
    const sha256 = crypto.createHash('sha256').update(data).digest('hex');
    await review.update({ sha256, file_size: data.length });
    return { sha256, size: data.length };
  }

  async scheduleSnapshot(device) {
    const items = [];
    const bookings = await Booking.findAll({
      where: { billboard_id: device.billboard_id, status: 'confirmed', booking_date: { [Op.gte]: zonedParts().date } },
      include: [{ model: VideoReview, as: 'review', where: { status: 'approved' } }],
      order: [['booking_date', 'ASC'], ['start_time', 'ASC']],
    });
    for (const booking of bookings) {
      const media = await this.checksum(booking.review);
      items.push({
        bookingId: booking.id,
        videoId: booking.review_id,
        filename: booking.review.filename,
        mimeType: booking.review.mime_type,
        startsAt: new Date(wallClockToEpoch(booking.booking_date, booking.start_time)).toISOString(),
        endsAt: new Date(wallClockToEpoch(booking.booking_date, booking.end_time)).toISOString(),
        sha256: media.sha256,
        size: media.size,
        mediaPath: `/api/tv/media/${encodeURIComponent(booking.review_id)}?deviceId=${encodeURIComponent(device.id)}`,
      });
    }
    return { type: 'schedule.snapshot', revision: await this.revision(), serverTime: new Date().toISOString(), timezone, items };
  }

  async markSeen(device, appVersion = '') {
    const timestamp = new Date();
    await device.update({ last_seen_at: timestamp, app_version: String(appVersion).slice(0, 40) });
    return timestamp;
  }

  async listDevices(user) {
    const devices = await TvDevice.findAll({
      where: user.role === 'admin' ? {} : { owner_id: user.id },
      include: [
        { model: Billboard, as: 'billboard', attributes: ['name'] },
        { model: User, as: 'owner', attributes: ['name'] },
      ],
      order: [['created_at', 'DESC']],
    });
    return devices.map((device) => ({
      id: device.id, name: device.name, billboard_id: device.billboard_id,
      billboard_name: device.billboard.name, owner_name: device.owner.name,
      status: device.status, app_version: device.app_version, paired_at: device.paired_at,
      last_seen_at: device.last_seen_at,
      installation_id: device.installation_id,
      device_metadata: (() => { try { return JSON.parse(device.device_metadata); } catch { return {}; } })(),
      latitude: device.latitude,
      longitude: device.longitude,
      location_accuracy: device.location_accuracy,
      online: Boolean(device.last_seen_at && Date.now() - new Date(device.last_seen_at).getTime() < DEVICE_STALE_MS),
    }));
  }

  async revokeDevice(user, id) {
    const device = await TvDevice.findByPk(id);
    if (!device || (user.role !== 'admin' && device.owner_id !== user.id)) throw fail(404, 'TV not found.');
    await this._revokeDeviceRecord(device);
    return { message: 'TV access revoked.' };
  }

  async unpairDevice(device) {
    await this._revokeDeviceRecord(device);
    return { message: 'TV unpaired.' };
  }

  async _revokeDeviceRecord(device) {
    await device.update({ status: 'revoked', token_hash: '' });
    const socket = this.clients.get(device.id);
    if (socket?.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify({ type: 'device.revoked' }));
      socket.close(4001, 'Device revoked');
    }
  }

  async recordEvent(device, body) {
    const eventType = String(body.type || '').slice(0, 50);
    if (!['media.downloaded', 'playback.started', 'playback.finished', 'playback.failed'].includes(eventType)) throw fail(400, 'Unknown TV event type.');
    if (body.bookingId && !await Booking.findOne({ where: { id: body.bookingId, billboard_id: device.billboard_id } })) {
      throw fail(404, 'Booking not found for this TV.');
    }
    await TvPlaybackEvent.create({
      device_id: device.id, booking_id: body.bookingId || null, event_type: eventType,
      details: String(body.details || '').slice(0, 500), created_at: new Date(),
    });
    return { accepted: true };
  }

  async mediaFor(device, reviewId) {
    const booking = await Booking.findOne({
      where: { billboard_id: device.billboard_id, review_id: reviewId, status: 'confirmed' },
      include: [{ model: VideoReview, as: 'review', where: { status: 'approved' } }],
    });
    if (!booking) throw fail(404, 'Approved media not found for this TV.');
    return booking.review;
  }

  async streamMedia(req, res, device, reviewId) {
    const review = await this.mediaFor(device, reviewId);
    let stat;
    try { stat = await fs.promises.stat(review.file_path); } catch { throw fail(404, 'Advertisement file not found.'); }
    let start = 0; let end = stat.size - 1; let status = 200;
    const range = String(req.headers.range || '');
    if (range) {
      const match = /^bytes=(\d*)-(\d*)$/.exec(range);
      if (!match) throw fail(416, 'Invalid byte range.');
      start = match[1] ? Number(match[1]) : Math.max(0, stat.size - Number(match[2] || 0));
      if (match[2]) end = Math.min(end, Number(match[2]));
      if (!Number.isSafeInteger(start) || start < 0 || start >= stat.size || end < start) throw fail(416, 'Invalid byte range.');
      status = 206;
    }
    const headers = { 'content-type': review.mime_type, 'content-length': String(end - start + 1), 'accept-ranges': 'bytes', 'cache-control': 'private, max-age=3600' };
    if (status === 206) headers['content-range'] = `bytes ${start}-${end}/${stat.size}`;
    res.writeHead(status, headers);
    if (req.method === 'HEAD') return res.end();
    fs.createReadStream(review.file_path, { start, end }).pipe(res);
  }

  async bumpAndBroadcast(billboardId, reason = 'schedule.updated') {
    const revision = await sequelize.transaction((transaction) => this.nextRevision(transaction));
    const devices = await TvDevice.findAll({ where: { billboard_id: billboardId, status: 'active' }, include: [{ model: Billboard, as: 'billboard' }] });
    for (const device of devices) {
      const socket = this.clients.get(device.id);
      if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ ...await this.scheduleSnapshot(device), reason, revision }));
    }
    return revision;
  }

  attachSocketServer(server) {
    this.wss = new WebSocketServer({ noServer: true });
    server.on('upgrade', (req, socket, head) => {
      let url;
      try { url = new URL(req.url, 'http://localhost'); } catch { socket.destroy(); return; }
      if (url.pathname !== '/api/tv/socket') return socket.destroy();
      this.wss.handleUpgrade(req, socket, head, (ws) => this.wss.emit('connection', ws));
    });
    this.wss.on('connection', (ws) => {
      const authTimer = setTimeout(() => ws.close(4003, 'Authentication timeout'), 10000);
      ws.on('message', async (raw) => {
        try {
          const message = JSON.parse(String(raw));
          if (message.type === 'device.hello') {
            const device = await this.authenticate(message.deviceId, message.token);
            clearTimeout(authTimer);
            ws.device = device;
            this.clients.get(device.id)?.close(4000, 'Replaced by newer connection');
            this.clients.set(device.id, ws);
            await this.markSeen(device, message.appVersion);
            ws.send(JSON.stringify(await this.scheduleSnapshot(device)));
          } else if (message.type === 'device.heartbeat' && ws.device) {
            await this.markSeen(ws.device, message.appVersion);
            ws.send(JSON.stringify({ type: 'device.heartbeat.ack', serverTime: new Date().toISOString() }));
          }
        } catch (error) {
          ws.send(JSON.stringify({ type: 'error', message: error.status ? error.message : 'Invalid socket message.' }));
        }
      });
      ws.on('close', () => {
        clearTimeout(authTimer);
        if (ws.device && this.clients.get(ws.device.id) === ws) this.clients.delete(ws.device.id);
      });
    });
  }

  close() {
    for (const socket of this.clients.values()) socket.close(1001, 'Server shutting down');
    this.wss?.close();
  }
}

module.exports = new TvService();
