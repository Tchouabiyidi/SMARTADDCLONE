'use strict';

const { Op } = require('sequelize');
const { Booking } = require('../models');
const { fail } = require('../utils/errors');
const { zonedParts } = require('../utils/time');

const validTime = (value) => typeof value === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(value);

async function expirePendingBookings(transaction) {
  await Booking.update(
    { status: 'expired', updated_at: new Date() },
    { where: { status: 'pending_payment', created_at: { [Op.lt]: new Date(Date.now() - 15 * 60 * 1000) } }, transaction },
  );
}

async function ensureSlotAvailable({ billboardId, date, start, end, excludeBookingId = '', transaction }) {
  await expirePendingBookings(transaction);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || Number.isNaN(Date.parse(`${date}T00:00:00Z`))) throw fail(400, 'Choose a valid date.');
  if (!validTime(start) || !validTime(end) || start >= end) throw fail(400, 'Choose a valid time range.');
  const current = zonedParts();
  if (date < current.date || (date === current.date && end <= current.time)) throw fail(400, 'Choose a future time slot.');
  const where = {
    billboard_id: billboardId,
    booking_date: date,
    status: { [Op.in]: ['pending_payment', 'confirmed'] },
    start_time: { [Op.lt]: end },
    end_time: { [Op.gt]: start },
  };
  if (excludeBookingId) where.id = { [Op.ne]: excludeBookingId };
  if (await Booking.findOne({ where, transaction })) throw fail(409, 'That time slot is already reserved. Choose another time.');
}

module.exports = { ensureSlotAvailable, expirePendingBookings, validTime };
