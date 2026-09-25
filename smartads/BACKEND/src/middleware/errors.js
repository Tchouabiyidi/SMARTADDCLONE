'use strict';

function notFound(_req, res) {
  res.status(404).json({ error: 'Route not found.' });
}

function errorHandler(error, _req, res, _next) {
  const status = Number(error.status) || (error.name === 'SequelizeUniqueConstraintError' ? 409 : 500);
  if (status >= 500) console.error('SMARTADS request failed:', error);
  res.status(status).json({ error: status >= 500 ? 'Something went wrong on the server.' : error.message });
}

module.exports = { errorHandler, notFound };
