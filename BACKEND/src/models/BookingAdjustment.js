'use strict';
module.exports = (sequelize, DataTypes) => sequelize.define('BookingAdjustment', {
  id: { type: DataTypes.STRING, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  booking_id: { type: DataTypes.STRING, allowNull: false },
  admin_id: { type: DataTypes.STRING, allowNull: false },
  action: { type: DataTypes.STRING, allowNull: false },
  previous_end_time: DataTypes.STRING(5),
  new_end_time: DataTypes.STRING(5),
  reason: { type: DataTypes.TEXT, allowNull: false, defaultValue: '' },
  created_at: { type: DataTypes.DATE, allowNull: false },
}, { tableName: 'booking_adjustments' });
