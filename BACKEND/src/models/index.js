'use strict';

const { DataTypes } = require('sequelize');
const { sequelize } = require('../config/database');

const User = require('./User')(sequelize, DataTypes);
const Billboard = require('./Billboard')(sequelize, DataTypes);
const VideoReview = require('./VideoReview')(sequelize, DataTypes);
const Booking = require('./Booking')(sequelize, DataTypes);
const Payment = require('./Payment')(sequelize, DataTypes);
const TvDevice = require('./TvDevice')(sequelize, DataTypes);
const TvPairingSession = require('./TvPairingSession')(sequelize, DataTypes);
const TvPlaybackEvent = require('./TvPlaybackEvent')(sequelize, DataTypes);
const BookingAdjustment = require('./BookingAdjustment')(sequelize, DataTypes);
const AppState = require('./AppState')(sequelize, DataTypes);

User.hasMany(Billboard, { foreignKey: 'owner_id', as: 'billboards' });
Billboard.belongsTo(User, { foreignKey: 'owner_id', as: 'owner' });
User.hasMany(VideoReview, { foreignKey: 'user_id', as: 'video_reviews' });
VideoReview.belongsTo(User, { foreignKey: 'user_id', as: 'advertiser' });
User.hasMany(Booking, { foreignKey: 'advertiser_id', as: 'bookings' });
Booking.belongsTo(User, { foreignKey: 'advertiser_id', as: 'advertiser' });
Billboard.hasMany(Booking, { foreignKey: 'billboard_id', as: 'bookings' });
Booking.belongsTo(Billboard, { foreignKey: 'billboard_id', as: 'billboard' });
VideoReview.hasMany(Booking, { foreignKey: 'review_id', as: 'bookings' });
Booking.belongsTo(VideoReview, { foreignKey: 'review_id', as: 'review' });
Booking.hasOne(Payment, { foreignKey: 'booking_id', as: 'payment' });
Payment.belongsTo(Booking, { foreignKey: 'booking_id', as: 'booking' });
Billboard.hasMany(TvDevice, { foreignKey: 'billboard_id', as: 'tv_devices' });
TvDevice.belongsTo(Billboard, { foreignKey: 'billboard_id', as: 'billboard' });
User.hasMany(TvDevice, { foreignKey: 'owner_id', as: 'tv_devices' });
TvDevice.belongsTo(User, { foreignKey: 'owner_id', as: 'owner' });

module.exports = {
  sequelize, User, Billboard, VideoReview, Booking, Payment, TvDevice,
  TvPairingSession, TvPlaybackEvent, BookingAdjustment, AppState,
};
