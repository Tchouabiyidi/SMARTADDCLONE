'use strict';
module.exports = (sequelize, DataTypes) => sequelize.define('TvDevice', {
  id: { type: DataTypes.STRING, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  owner_id: { type: DataTypes.STRING, allowNull: false },
  billboard_id: { type: DataTypes.STRING, allowNull: false },
  name: { type: DataTypes.STRING(80), allowNull: false },
  installation_id: { type: DataTypes.STRING, allowNull: false, unique: true },
  hardware_hash: { type: DataTypes.STRING, unique: true },
  device_metadata: { type: DataTypes.TEXT, allowNull: false, defaultValue: '{}' },
  latitude: DataTypes.DOUBLE,
  longitude: DataTypes.DOUBLE,
  location_accuracy: DataTypes.DOUBLE,
  token_hash: { type: DataTypes.STRING, allowNull: false, defaultValue: '' },
  status: { type: DataTypes.STRING, allowNull: false, defaultValue: 'active' },
  last_seen_at: DataTypes.DATE,
  app_version: DataTypes.STRING(40),
  paired_at: { type: DataTypes.DATE, allowNull: false },
  created_at: { type: DataTypes.DATE, allowNull: false },
}, { tableName: 'tv_devices' });
