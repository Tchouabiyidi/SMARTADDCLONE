'use strict';
module.exports = (sequelize, DataTypes) => sequelize.define('TvPlaybackEvent', {
  id: { type: DataTypes.STRING, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  device_id: { type: DataTypes.STRING, allowNull: false },
  booking_id: DataTypes.STRING,
  event_type: { type: DataTypes.STRING(50), allowNull: false },
  details: { type: DataTypes.TEXT, allowNull: false, defaultValue: '' },
  created_at: { type: DataTypes.DATE, allowNull: false },
}, { tableName: 'tv_playback_events' });
