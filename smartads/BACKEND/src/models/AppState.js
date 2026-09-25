'use strict';
module.exports = (sequelize, DataTypes) => sequelize.define('AppState', {
  key: { type: DataTypes.STRING, primaryKey: true },
  value: { type: DataTypes.TEXT, allowNull: false },
}, { tableName: 'app_state' });
