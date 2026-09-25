'use strict';

const { Op } = require('sequelize');
const { Billboard, Booking, User } = require('../models');
const tvService = require('../services/tv.service');
const { fail } = require('../utils/errors');

const serialize = (board) => ({ ...board.toJSON(), owner_name: board.owner?.name });

async function list(req, res) {
  const where = ['owner', 'admin'].includes(req.user.role) ? {} : { is_active: true };
  const boards = await Billboard.findAll({ where, include: [{ model: User, as: 'owner', attributes: ['name'] }], order: [['created_at', 'DESC']] });
  res.json({ billboards: boards.map(serialize) });
}

async function create(req, res) {
  const name = String(req.body.name || '').trim();
  const location = String(req.body.location || '').trim();
  const description = String(req.body.description || '').trim();
  const price = Number(req.body.pricePerHour);
  if (name.length < 2 || !location || !Number.isFinite(price) || price <= 0) throw fail(400, 'Add a billboard name, location, and positive hourly price.');
  const billboard = await Billboard.create({ owner_id: req.user.id, name, location, description, price_per_hour: price, is_active: true, created_at: new Date() });
  res.status(201).json({ billboard });
}

async function availability(req, res) {
  const date = String(req.query.date || '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw fail(400, 'Choose a valid date.');
  const billboard = await Billboard.findOne({ where: { id: req.params.id, is_active: true } });
  if (!billboard) throw fail(404, 'Billboard is unavailable.');
  const bookings = await Booking.findAll({
    where: { billboard_id: billboard.id, booking_date: date, status: { [Op.in]: ['pending_payment', 'confirmed'] } },
    attributes: ['start_time', 'end_time'], order: [['start_time', 'ASC']],
  });
  res.json({ date, bookedSlots: bookings });
}

async function update(req, res) {
  const billboard = await Billboard.findOne({ where: { id: req.params.id, owner_id: req.user.id } });
  if (!billboard) throw fail(404, 'Billboard not found.');
  billboard.is_active = Boolean(req.body.isActive);
  await billboard.save();
  await tvService.bumpAndBroadcast(billboard.id, billboard.is_active ? 'billboard.activated' : 'billboard.deactivated');
  res.json({ billboard });
}

module.exports = { availability, create, list, update };
