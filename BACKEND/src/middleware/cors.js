'use strict';

function cors(req, res, next) {
  res.set({
    'access-control-allow-origin': process.env.CORS_ORIGIN || '*',
    'access-control-allow-headers': 'content-type, authorization',
    'access-control-allow-methods': 'GET, POST, PATCH, DELETE, OPTIONS',
  });
  if (req.method === 'OPTIONS') return res.status(204).end();
  next();
}

module.exports = { cors };
