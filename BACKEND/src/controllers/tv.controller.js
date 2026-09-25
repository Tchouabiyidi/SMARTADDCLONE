'use strict';

const tvService = require('../services/tv.service');

async function startPairing(req, res) {
  res.status(201).json(await tvService.startPairing(req.body));
}
async function pairingStatus(req, res) {
  res.json(await tvService.pairingStatus(req.params.id, String(req.query.secret || '')));
}
async function lookupByUserCode(req, res) {
  res.json(await tvService.lookupByUserCode(req.query.code));
}
async function approvePairing(req, res) {
  res.json(await tvService.approvePairing(req.user, req.params.id, req.body));
}
async function listDevices(req, res) {
  res.json({ devices: await tvService.listDevices(req.user) });
}
async function revokeDevice(req, res) {
  res.json(await tvService.revokeDevice(req.user, req.params.id));
}
async function unpairDevice(req, res) {
  res.json(await tvService.unpairDevice(req.tvDevice));
}
async function schedule(req, res) {
  res.json(await tvService.scheduleSnapshot(req.tvDevice));
}
async function heartbeat(req, res) {
  res.json({ serverTime: await tvService.markSeen(req.tvDevice, req.body.appVersion) });
}
async function event(req, res) {
  res.status(202).json(await tvService.recordEvent(req.tvDevice, req.body));
}
async function media(req, res) {
  await tvService.streamMedia(req, res, req.tvDevice, req.params.reviewId);
}
async function authenticateDevice(req, _res, next) {
  try {
    req.tvDevice = await tvService.authenticateRequest(req);
    next();
  } catch (error) { next(error); }
}

module.exports = {
  approvePairing, authenticateDevice, event, heartbeat, listDevices,
  lookupByUserCode, media, pairingStatus, revokeDevice, schedule, startPairing,
  unpairDevice,
};
