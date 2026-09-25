'use strict';

const fs = require('node:fs');
const { Billboard, Booking, BookingAdjustment, Payment, TvDevice, TvPairingSession, TvPlaybackEvent, User, VideoReview, sequelize } = require('../models');
const { ensureSlotAvailable, validTime } = require('../services/booking.service');
const tvService = require('../services/tv.service');
const { fail } = require('../utils/errors');

async function listUsers(_req, res) {
  res.json({ users: await User.findAll({ attributes: ['id', 'name', 'email', 'role', 'status', 'created_at'], order: [['created_at', 'DESC']] }) });
}

async function updateUser(req, res) {
  const status = String(req.body.status || '');
  if (!['active', 'suspended'].includes(status)) throw fail(400, 'Status must be active or suspended.');
  if (req.params.id === req.user.id) throw fail(400, 'You cannot suspend your own admin account.');
  const user = await User.findByPk(req.params.id);
  if (!user) throw fail(404, 'User not found.');
  await user.update({ status });
  res.json({ message: `User ${status}.` });
}

async function deleteUser(req, res) {
  if (req.params.id === req.user.id) throw fail(400, 'You cannot delete your own admin account.');
  const user = await User.findByPk(req.params.id);
  if (!user) throw fail(404, 'User not found.');
  const reviews = await VideoReview.findAll({ where: { user_id: user.id } });
  await sequelize.transaction(async (transaction) => {
    const boards = await Billboard.findAll({ where: { owner_id: user.id }, attributes: ['id'], transaction });
    const boardIds = boards.map((board) => board.id);
    const ownBookings = await Booking.findAll({ where: { advertiser_id: user.id }, attributes: ['id'], transaction });
    const boardBookings = boardIds.length ? await Booking.findAll({ where: { billboard_id: boardIds }, attributes: ['id'], transaction }) : [];
    const bookingIds = [...new Set([...ownBookings, ...boardBookings].map((booking) => booking.id))];
    if (bookingIds.length) {
      await TvPlaybackEvent.destroy({ where: { booking_id: bookingIds }, transaction });
      await BookingAdjustment.destroy({ where: { booking_id: bookingIds }, transaction });
      await Payment.destroy({ where: { booking_id: bookingIds }, transaction });
      await Booking.destroy({ where: { id: bookingIds }, transaction });
    }
    if (boardIds.length) {
      const devices = await TvDevice.findAll({ where: { billboard_id: boardIds }, attributes: ['id'], transaction });
      const deviceIds = devices.map((device) => device.id);
      if (deviceIds.length) await TvPlaybackEvent.destroy({ where: { device_id: deviceIds }, transaction });
      await TvPairingSession.destroy({ where: { billboard_id: boardIds }, transaction });
      await TvDevice.destroy({ where: { billboard_id: boardIds }, transaction });
      await Billboard.destroy({ where: { id: boardIds }, transaction });
    }
    await VideoReview.destroy({ where: { user_id: user.id }, transaction });
    await user.destroy({ transaction });
  });
  for (const review of reviews) await fs.promises.unlink(review.file_path).catch(() => {});
  res.json({ message: 'User and related data deleted.' });
}

async function stopBooking(req, res) {
  const booking = await Booking.findByPk(req.params.id);
  if (!booking) throw fail(404, 'Booking not found.');
  if (booking.status !== 'confirmed') throw fail(409, 'Only a confirmed booking can be stopped.');
  const reason = String(req.body.reason || '').trim().slice(0, 300); const timestamp = new Date();
  await sequelize.transaction(async (transaction) => {
    await booking.update({ status: 'stopped', stopped_at: timestamp, stopped_by: req.user.id, stop_reason: reason, updated_at: timestamp, schedule_revision: booking.schedule_revision + 1 }, { transaction });
    await BookingAdjustment.create({ booking_id: booking.id, admin_id: req.user.id, action: 'stopped', previous_end_time: booking.end_time, reason, created_at: timestamp }, { transaction });
  });
  await tvService.bumpAndBroadcast(booking.billboard_id, 'booking.stopped');
  res.json({ message: 'Advertisement stopped.', booking });
}

async function extendBooking(req, res) {
  const booking = await Booking.findByPk(req.params.id);
  if (!booking) throw fail(404, 'Booking not found.');
  if (booking.status !== 'confirmed') throw fail(409, 'Only a confirmed booking can be extended.');
  const endTime = String(req.body.endTime || '');
  if (!validTime(endTime) || endTime <= booking.end_time) throw fail(400, 'Choose an end time later than the current end time.');
  await ensureSlotAvailable({ billboardId: booking.billboard_id, date: booking.booking_date, start: booking.start_time, end: endTime, excludeBookingId: booking.id });
  const previousEnd = booking.end_time; const reason = String(req.body.reason || '').trim().slice(0, 300);
  await sequelize.transaction(async (transaction) => {
    await booking.update({ end_time: endTime, updated_at: new Date(), schedule_revision: booking.schedule_revision + 1 }, { transaction });
    await BookingAdjustment.create({ booking_id: booking.id, admin_id: req.user.id, action: 'extended', previous_end_time: previousEnd, new_end_time: endTime, reason, created_at: new Date() }, { transaction });
  });
  await tvService.bumpAndBroadcast(booking.billboard_id, 'booking.extended');
  res.json({ message: 'Advertisement period extended.', booking });
}

module.exports = { deleteUser, extendBooking, listUsers, stopBooking, updateUser };
