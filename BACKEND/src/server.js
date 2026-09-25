'use strict';
const http = require('node:http');
const { app } = require('./app');
const { initializeDatabase } = require('./config/initialize-database');
const { sequelize, User } = require('./models');
const tvService = require('./services/tv.service');
const { hashPassword } = require('./utils/passwords');
const port = Number(process.env.PORT || 3000);
const server = http.createServer(app);
async function ensureAdmin() {
  if (!process.env.ADMIN_EMAIL || !process.env.ADMIN_PASSWORD) return;
  const email = process.env.ADMIN_EMAIL.trim().toLowerCase();
  await User.findOrCreate({ where: { email }, defaults: { name: 'SMARTADS Admin', password_hash: hashPassword(process.env.ADMIN_PASSWORD), role: 'admin', status: 'active', created_at: new Date() } });
}
async function start() {
  await initializeDatabase();
  await ensureAdmin();
  tvService.attachSocketServer(server);
  server.listen(port, '0.0.0.0', () => console.log(`SMARTADS API ready on http://localhost:${port}`));
}
async function stop() {
  tvService.close();
  server.close(async () => { await sequelize.close(); process.exit(0); });
}
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
start().catch((error) => { console.error('SMARTADS failed to start:', error); process.exit(1); });
