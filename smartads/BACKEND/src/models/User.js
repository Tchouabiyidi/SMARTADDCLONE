'use strict';
module.exports = (sequelize, DataTypes) => sequelize.define('User', {
  id: { type: DataTypes.STRING, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  name: { type: DataTypes.STRING(80), allowNull: false },
  email: { type: DataTypes.STRING(254), allowNull: false, unique: true },
  password_hash: { type: DataTypes.TEXT, allowNull: false },
  role: { type: DataTypes.ENUM('advertiser', 'owner', 'admin'), allowNull: false },
  status: { type: DataTypes.ENUM('active', 'suspended'), allowNull: false, defaultValue: 'active' },
  created_at: { type: DataTypes.DATE, allowNull: false },
}, { tableName: 'users' });
