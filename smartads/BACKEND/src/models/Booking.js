'use strict';
module.exports = (sequelize, DataTypes) => sequelize.define('Booking', {
  id: { type: DataTypes.STRING, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  advertiser_id: { type: DataTypes.STRING, allowNull: false },
  billboard_id: { type: DataTypes.STRING, allowNull: false },
  review_id: { type: DataTypes.STRING, allowNull: false },
  booking_date: { type: DataTypes.STRING(10), allowNull: false },
  start_time: { type: DataTypes.STRING(5), allowNull: false },
  end_time: { type: DataTypes.STRING(5), allowNull: false },
  amount: { type: DataTypes.DOUBLE, allowNull: false },
  status: { type: DataTypes.STRING, allowNull: false, defaultValue: 'pending_payment' },
  schedule_revision: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 1 },
  stopped_at: DataTypes.DATE,
  stopped_by: DataTypes.STRING,
  stop_reason: { type: DataTypes.TEXT, allowNull: false, defaultValue: '' },
  created_at: { type: DataTypes.DATE, allowNull: false },
  updated_at: { type: DataTypes.DATE, allowNull: false },
}, { tableName: 'bookings', indexes: [{ fields: ['billboard_id', 'booking_date', 'start_time', 'end_time'] }] });
