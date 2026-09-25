'use strict';
module.exports = (sequelize, DataTypes) => sequelize.define('Payment', {
  id: { type: DataTypes.STRING, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  booking_id: { type: DataTypes.STRING, allowNull: false, unique: true },
  amount: { type: DataTypes.DOUBLE, allowNull: false },
  provider: { type: DataTypes.STRING, allowNull: false },
  status: { type: DataTypes.STRING, allowNull: false },
  created_at: { type: DataTypes.DATE, allowNull: false },
}, { tableName: 'payments' });
