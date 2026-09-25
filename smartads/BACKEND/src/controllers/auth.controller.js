'use strict';

const { User } = require('../models');
const { fail } = require('../utils/errors');
const { hashPassword, verifyPassword } = require('../utils/passwords');
const { tokenFor } = require('../utils/tokens');

const publicUser = (user) => ({ id: user.id, name: user.name, email: user.email, role: user.role, status: user.status });

async function signup(req, res) {
  const name = String(req.body.name || '').trim();
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '');
  const role = String(req.body.role || '');
  if (name.length < 2 || name.length > 80) throw fail(400, 'Enter your name (2–80 characters).');
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw fail(400, 'Enter a valid email address.');
  if (password.length < 8) throw fail(400, 'Password must be at least 8 characters.');
  if (!['advertiser', 'owner'].includes(role)) throw fail(400, 'Choose Advertiser or Billboard Owner.');
  if (await User.findOne({ where: { email } })) throw fail(409, 'An account with that email already exists.');
  const user = await User.create({ name, email, password_hash: hashPassword(password), role, status: 'active', created_at: new Date() });
  res.status(201).json({ token: tokenFor(user), user: publicUser(user) });
}

async function login(req, res) {
  const email = String(req.body.email || '').trim().toLowerCase();
  const user = await User.findOne({ where: { email } });
  if (!user || !verifyPassword(String(req.body.password || ''), user.password_hash)) throw fail(401, 'Email or password is incorrect.');
  if (user.status !== 'active') throw fail(403, 'This account is suspended. Contact SMARTADS support.');
  res.json({ token: tokenFor(user), user: publicUser(user) });
}

const me = async (req, res) => res.json({ user: publicUser(req.user) });

module.exports = { login, me, signup };
