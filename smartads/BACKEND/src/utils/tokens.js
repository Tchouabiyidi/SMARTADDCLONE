'use strict';

const crypto = require('node:crypto');
const { fail } = require('./errors');

const secret = process.env.JWT_SECRET || 'smartads-local-demo-secret-change-me';

function tokenFor(user) {
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({ sub: user.id, exp: Date.now() + 7 * 86400000 })).toString('base64url');
  const signature = crypto.createHmac('sha256', secret).update(`${header}.${payload}`).digest('base64url');
  return `${header}.${payload}.${signature}`;
}

function verifyToken(token) {
  const [header, payload, signature] = String(token || '').split('.');
  if (!header || !payload || !signature) throw fail(401, 'Please sign in to continue.');
  const expected = crypto.createHmac('sha256', secret).update(`${header}.${payload}`).digest();
  const supplied = Buffer.from(signature, 'base64url');
  if (expected.length !== supplied.length || !crypto.timingSafeEqual(expected, supplied)) throw fail(401, 'Invalid session.');
  let claims;
  try { claims = JSON.parse(Buffer.from(payload, 'base64url').toString()); } catch { throw fail(401, 'Invalid session.'); }
  if (!claims.sub || claims.exp < Date.now()) throw fail(401, 'Session expired. Please sign in again.');
  return claims;
}

module.exports = { tokenFor, verifyToken };
