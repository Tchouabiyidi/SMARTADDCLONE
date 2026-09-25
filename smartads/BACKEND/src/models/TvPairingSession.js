'use strict';
module.exports = (sequelize, DataTypes) => sequelize.define('TvPairingSession', {
  id: { type: DataTypes.STRING, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  secret_hash: { type: DataTypes.STRING, allowNull: false },
  user_code: { type: DataTypes.STRING, allowNull: false },
  device_name: { type: DataTypes.STRING(80), allowNull: false },
  installation_id: { type: DataTypes.STRING, allowNull: false },
  hardware_hash: DataTypes.STRING,
  device_metadata: { type: DataTypes.TEXT, allowNull: false, defaultValue: '{}' },
  latitude: DataTypes.DOUBLE,
  longitude: DataTypes.DOUBLE,
  location_accuracy: DataTypes.DOUBLE,
  status: { type: DataTypes.STRING, allowNull: false, defaultValue: 'pending' },
  billboard_id: DataTypes.STRING,
  approved_by: DataTypes.STRING,
  device_id: DataTypes.STRING,
  expires_at: { type: DataTypes.DATE, allowNull: false },
  created_at: { type: DataTypes.DATE, allowNull: false },
}, { tableName: 'tv_pairing_sessions' });
