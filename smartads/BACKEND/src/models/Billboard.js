'use strict';
module.exports = (sequelize, DataTypes) => sequelize.define('Billboard', {
  id: { type: DataTypes.STRING, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  owner_id: { type: DataTypes.STRING, allowNull: false },
  name: { type: DataTypes.STRING(120), allowNull: false },
  location: { type: DataTypes.STRING(250), allowNull: false },
  description: { type: DataTypes.TEXT, allowNull: false, defaultValue: '' },
  price_per_hour: { type: DataTypes.DOUBLE, allowNull: false },
  is_active: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: true },
  created_at: { type: DataTypes.DATE, allowNull: false },
}, { tableName: 'billboards' });
