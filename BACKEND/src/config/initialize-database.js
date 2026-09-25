'use strict';

const { DataTypes } = require('sequelize');
const models = require('../models');

async function addMissingColumns(table, columns) {
  const queryInterface = models.sequelize.getQueryInterface();
  const existing = await queryInterface.describeTable(table);
  for (const [name, definition] of Object.entries(columns)) {
    if (!existing[name]) await queryInterface.addColumn(table, name, definition);
  }
}

async function initializeDatabase() {
  await models.sequelize.query('PRAGMA foreign_keys = ON');
  await models.sequelize.sync();
  await addMissingColumns('video_reviews', {
    sha256: { type: DataTypes.STRING, allowNull: false, defaultValue: '' },
    file_size: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  });
  await addMissingColumns('bookings', {
    updated_at: { type: DataTypes.DATE, allowNull: false, defaultValue: '' },
    schedule_revision: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 1 },
    stopped_at: { type: DataTypes.DATE },
    stopped_by: { type: DataTypes.STRING },
    stop_reason: { type: DataTypes.TEXT, allowNull: false, defaultValue: '' },
  });
  await addMissingColumns('tv_pairing_sessions', {
    installation_id: { type: DataTypes.STRING, allowNull: false, defaultValue: '' },
    hardware_hash: { type: DataTypes.STRING },
    device_metadata: { type: DataTypes.TEXT, allowNull: false, defaultValue: '{}' },
    latitude: { type: DataTypes.DOUBLE },
    longitude: { type: DataTypes.DOUBLE },
    location_accuracy: { type: DataTypes.DOUBLE },
  });
  await addMissingColumns('tv_devices', {
    installation_id: { type: DataTypes.STRING, allowNull: false, defaultValue: '' },
    hardware_hash: { type: DataTypes.STRING },
    device_metadata: { type: DataTypes.TEXT, allowNull: false, defaultValue: '{}' },
    latitude: { type: DataTypes.DOUBLE },
    longitude: { type: DataTypes.DOUBLE },
    location_accuracy: { type: DataTypes.DOUBLE },
  });
  await models.sequelize.query("CREATE UNIQUE INDEX IF NOT EXISTS tv_devices_installation_unique ON tv_devices(installation_id) WHERE installation_id <> ''");
  await models.sequelize.query("CREATE UNIQUE INDEX IF NOT EXISTS tv_devices_hardware_unique ON tv_devices(hardware_hash) WHERE hardware_hash IS NOT NULL AND hardware_hash <> ''");
  await models.AppState.findOrCreate({ where: { key: 'tv_schedule_revision' }, defaults: { value: '0' } });
}

module.exports = { initializeDatabase };
