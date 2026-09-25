'use strict';

const { Billboard, Booking, Payment, User, VideoReview, sequelize } = require('../models');
const { ensureSlotAvailable } = require('../services/booking.service');
const tvService = require('../services/tv.service');
const { fail } = require('../utils/errors');

const serialize = (booking) => ({
  ...booking.toJSON(),
  billboard_name: booking.billboard?.name,
  location: booking.billboard?.location,
  advertiser_name: booking.advertiser?.name,
  billboard: undefined,
  advertiser: undefined,
});

async function list(req, res) {
  const where = {};
  if (req.user.role === 'advertiser') where.advertiser_id = req.user.id;
  if (req.user.role === 'owner') {
    const boards = await Billboard.findAll({ where: { owner_id: req.user.id }, attributes: ['id'] });
    where.billboard_id = boards.map((board) => board.id);
  }
  const bookings = await Booking.findAll({
    where,
    include: [
      { model: Billboard, as: 'billboard', attributes: ['name', 'location'] },
      { model: User, as: 'advertiser', attributes: ['name'] },
    ],
    order: [['booking_date', 'ASC'], ['start_time', 'ASC']],
  });
  res.json({ bookings: bookings.map(serialize) });
}

async function create(req, res) {
  const billboard = await Billboard.findOne({ where: { id: String(req.body.billboardId || ''), is_active: true } });
  if (!billboard) throw fail(404, 'That billboard is unavailable.');
  const review = await VideoReview.findOne({ where: { id: String(req.body.reviewId || ''), user_id: req.user.id, status: 'approved' } });
  if (!review) throw fail(400, 'Upload and pass the AI video review before booking.');
  const date = String(req.body.date || '');

  // Multi-slot support
  const rawSlots = Array.isArray(req.body.slots) && req.body.slots.length > 0 ? req.body.slots : null;
  if (rawSlots) {
    const createdBookings = [];
    await sequelize.transaction(async (transaction) => {
      for (const slotStart of rawSlots) {
        const start = String(slotStart);
        const hour = parseInt(start.split(':')[0], 10);
        const end = hour === 23 ? '23:59' : `${String(hour + 1).padStart(2, '0')}:00`;
        await ensureSlotAvailable({ billboardId: billboard.id, date, start, end, transaction });
        const startMinutes = Number(start.slice(0, 2)) * 60 + Number(start.slice(3));
        const endMinutes = Number(end.slice(0, 2)) * 60 + Number(end.slice(3));
        const amount = Math.round(billboard.price_per_hour * ((endMinutes - startMinutes) / 60) * 100) / 100;
        const timestamp = new Date();
        const booking = await Booking.create({
          advertiser_id: req.user.id, billboard_id: billboard.id, review_id: review.id,
          booking_date: date, start_time: start, end_time: end, amount,
          status: 'pending_payment', created_at: timestamp, updated_at: timestamp,
        }, { transaction });
        createdBookings.push(booking);
      }
    });
    return res.status(201).json({ bookings: createdBookings, booking: createdBookings[0] });
  }

  // Single slot fallback
  const start = String(req.body.startTime || ''); const end = String(req.body.endTime || '');
  await ensureSlotAvailable({ billboardId: billboard.id, date, start, end });
  const startMinutes = Number(start.slice(0, 2)) * 60 + Number(start.slice(3));
  const endMinutes = Number(end.slice(0, 2)) * 60 + Number(end.slice(3));
  const amount = Math.round(billboard.price_per_hour * ((endMinutes - startMinutes) / 60) * 100) / 100;
  const timestamp = new Date();
  const booking = await Booking.create({
    advertiser_id: req.user.id, billboard_id: billboard.id, review_id: review.id,
    booking_date: date, start_time: start, end_time: end, amount,
    status: 'pending_payment', created_at: timestamp, updated_at: timestamp,
  });
  res.status(201).json({ booking, bookings: [booking] });
}

async function pay(req, res) {
  const booking = await Booking.findOne({ where: { id: req.params.id, advertiser_id: req.user.id } });
  if (!booking) throw fail(404, 'Booking not found.');
  const provider = String(req.body.provider || '');
  const mobileNumber = String(req.body.mobileNumber || '').replace(/[\s().-]/g, '');
  if (!['MTN Mobile Money', 'Orange Money'].includes(provider)) throw fail(400, 'Choose MTN Mobile Money or Orange Money.');
  if (!/^(?:\+?237)?[26]\d{8}$/.test(mobileNumber)) throw fail(400, 'Enter a valid Cameroon mobile money number.');
  if (booking.status === 'confirmed') return res.json({ booking, payment: await Payment.findOne({ where: { booking_id: booking.id } }) });
  if (booking.status !== 'pending_payment') throw fail(409, 'This booking cannot be paid.');
  let payment;
  await sequelize.transaction(async (transaction) => {
    await ensureSlotAvailable({
      billboardId: booking.billboard_id, date: booking.booking_date, start: booking.start_time,
      end: booking.end_time, excludeBookingId: booking.id, transaction,
    });
    payment = await Payment.create({
      booking_id: booking.id, amount: booking.amount, provider, status: 'paid', created_at: new Date(),
    }, { transaction });
    await booking.update({ status: 'confirmed', updated_at: new Date() }, { transaction });
  });
  await tvService.bumpAndBroadcast(booking.billboard_id, 'booking.confirmed');
  res.json({ booking, payment, message: 'Simulated payment successful. No money was charged. Your advertisement is scheduled.' });
}

async function batchPay(req, res) {
  const bookingIds = Array.isArray(req.body.bookingIds) ? req.body.bookingIds : [];
  if (!bookingIds.length) throw fail(400, 'No bookings provided for payment.');
  const provider = String(req.body.provider || '');
  const mobileNumber = String(req.body.mobileNumber || '').replace(/[\s().-]/g, '');
  if (!['MTN Mobile Money', 'Orange Money'].includes(provider)) throw fail(400, 'Choose MTN Mobile Money or Orange Money.');
  if (!/^(?:\+?237)?[26]\d{8}$/.test(mobileNumber)) throw fail(400, 'Enter a valid Cameroon mobile money number.');

  const bookings = await Booking.findAll({
    where: { id: bookingIds, advertiser_id: req.user.id },
  });
  if (bookings.length !== bookingIds.length) throw fail(404, 'One or more bookings not found.');

  await sequelize.transaction(async (transaction) => {
    for (const booking of bookings) {
      if (booking.status === 'confirmed') continue;
      if (booking.status !== 'pending_payment') throw fail(409, `Booking ${booking.id} cannot be paid.`);
      await ensureSlotAvailable({
        billboardId: booking.billboard_id, date: booking.booking_date, start: booking.start_time,
        end: booking.end_time, excludeBookingId: booking.id, transaction,
      });
      await Payment.create({
        booking_id: booking.id, amount: booking.amount, provider, status: 'paid', created_at: new Date(),
      }, { transaction });
      await booking.update({ status: 'confirmed', updated_at: new Date() }, { transaction });
    }
  });

  const billboardIds = [...new Set(bookings.map((b) => b.billboard_id))];
  for (const bId of billboardIds) {
    await tvService.bumpAndBroadcast(bId, 'booking.confirmed');
  }

  res.json({ bookings, message: 'Simulated payment successful. All slots scheduled.' });
}

module.exports = { batchPay, create, list, pay };
