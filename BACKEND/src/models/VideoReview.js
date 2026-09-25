'use strict';
module.exports = (sequelize, DataTypes) => sequelize.define('VideoReview', {
  id: { type: DataTypes.STRING, primaryKey: true, defaultValue: DataTypes.UUIDV4 },
  user_id: { type: DataTypes.STRING, allowNull: false },
  filename: { type: DataTypes.STRING, allowNull: false },
  file_path: { type: DataTypes.TEXT, allowNull: false },
  mime_type: { type: DataTypes.STRING, allowNull: false },
  status: { type: DataTypes.STRING, allowNull: false },
  message: { type: DataTypes.TEXT, allowNull: false },
  sha256: { type: DataTypes.STRING, allowNull: false, defaultValue: '' },
  file_size: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  created_at: { type: DataTypes.DATE, allowNull: false },
}, { tableName: 'video_reviews' });
