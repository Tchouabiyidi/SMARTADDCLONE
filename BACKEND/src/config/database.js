'use strict';

const path = require('node:path');
const { Sequelize } = require('sequelize');

const sequelize = new Sequelize({
  dialect: 'sqlite',
  storage: process.env.DB_FILE || path.join(__dirname, '..', '..', 'smartads.sqlite'),
  logging: process.env.SQL_LOGGING === 'true' ? console.log : false,
  define: { timestamps: false, freezeTableName: true },
});

module.exports = { sequelize };
