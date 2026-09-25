'use strict';

const { User } = require('../models');
const { fail } = require('../utils/errors');
const { verifyToken } = require('../utils/tokens');

async function authenticate(req, _res, next) {
  try {
    const raw = String(req.headers.authorization || '');
    const claims = verifyToken(raw.startsWith('Bearer ') ? raw.slice(7) : '');
    const user = await User.findByPk(claims.sub, { attributes: ['id', 'name', 'email', 'role', 'status'] });
    if (!user || user.status !== 'active') throw fail(403, 'This account is unavailable.');
    req.user = user;
    next();
  } catch (error) { next(error); }
}

const requireRole = (...roles) => (req, _res, next) => roles.includes(req.user.role)
  ? next()
  : next(fail(403, 'You do not have permission to do that.'));

module.exports = { authenticate, requireRole };
