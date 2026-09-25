'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { initializeDatabase } = require('./config/initialize-database');
const {
  sequelize,
  User,
  Billboard,
  VideoReview,
  Booking,
  Payment,
  TvDevice,
  BookingAdjustment,
} = require('./models');
const { hashPassword } = require('./utils/passwords');
const { zonedParts } = require('./utils/time');

const uploadsDir = path.join(__dirname, '..', 'uploads');

async function seed() {
  console.log('🌱 Initializing database schema...');
  await initializeDatabase();
  await fs.promises.mkdir(uploadsDir, { recursive: true });

  console.log('🌱 Seeding SMARTADS demonstration data...');

  // 1. Seed Users (Admin, Owners, Advertisers)
  const usersData = [
    {
      id: 'usr_admin_001',
      name: 'SMARTADS Admin',
      email: 'admin@smartads.com',
      password: 'admin1234',
      role: 'admin',
      status: 'active',
    },
    {
      id: 'usr_owner_001',
      name: 'Marcelle Kamga (Premium Displays)',
      email: 'owner@smartads.com',
      password: 'owner1234',
      role: 'owner',
      status: 'active',
    },
    {
      id: 'usr_owner_002',
      name: 'Jean-Paul Ndedi (Urban Screens)',
      email: 'jean@smartads.com',
      password: 'owner1234',
      role: 'owner',
      status: 'active',
    },
    {
      id: 'usr_adv_001',
      name: 'Sarah Fotso (Fotso Tech Hub)',
      email: 'advertiser@smartads.com',
      password: 'advertiser1234',
      role: 'advertiser',
      status: 'active',
    },
    {
      id: 'usr_adv_002',
      name: 'Bob Ndongo (Express Delivery Co)',
      email: 'bob@smartads.com',
      password: 'advertiser1234',
      role: 'advertiser',
      status: 'active',
    },
  ];

  const userMap = {};
  for (const u of usersData) {
    const [user] = await User.findOrCreate({
      where: { email: u.email },
      defaults: {
        id: u.id,
        name: u.name,
        email: u.email,
        password_hash: hashPassword(u.password),
        role: u.role,
        status: u.status,
        created_at: new Date(),
      },
    });
    userMap[u.email] = user;
  }
  console.log(`✅ Seeded ${Object.keys(userMap).length} users.`);

  // 2. Seed Billboards
  const billboardsData = [
    {
      id: 'bb_akwa_001',
      owner_id: userMap['owner@smartads.com'].id,
      name: 'Akwa Central Mega Screen',
      location: 'Boulevard de la Liberté, Akwa, Douala',
      description: 'High-density commercial avenue with heavy pedestrian and vehicle traffic. 4K Ultra-HD P3 LED screen.',
      price_per_hour: 15000,
      is_active: true,
      created_at: new Date(Date.now() - 30 * 86400000),
    },
    {
      id: 'bb_bonanjo_002',
      owner_id: userMap['owner@smartads.com'].id,
      name: 'Bonanjo Administrative District LED',
      location: 'Rue de l’Hôpital, Bonanjo, Douala',
      description: 'Facing premier banks, embassies, and multinational headquarters. Prime executive audience.',
      price_per_hour: 18000,
      is_active: true,
      created_at: new Date(Date.now() - 25 * 86400000),
    },
    {
      id: 'bb_bastos_003',
      owner_id: userMap['jean@smartads.com'].id,
      name: 'Bastos Embassy Highway Display',
      location: 'Rond-Point Bastos, Yaoundé',
      description: 'Upscale diplomatic neighborhood digital screen with 24/7 high visibility.',
      price_per_hour: 20000,
      is_active: true,
      created_at: new Date(Date.now() - 20 * 86400000),
    },
    {
      id: 'bb_deido_004',
      owner_id: userMap['jean@smartads.com'].id,
      name: 'Deido Grand Roundabout Billboard',
      location: 'Carrefour des Fleurs, Deido, Douala',
      description: 'Vibrant junction connecting Douala North and City Center. Maximum impression volume.',
      price_per_hour: 12000,
      is_active: true,
      created_at: new Date(Date.now() - 15 * 86400000),
    },
  ];

  const billboardMap = {};
  for (const b of billboardsData) {
    const [board] = await Billboard.findOrCreate({
      where: { id: b.id },
      defaults: b,
    });
    billboardMap[b.id] = board;
  }
  console.log(`✅ Seeded ${Object.keys(billboardMap).length} billboards.`);

  // 3. Seed TV Devices for playback simulation
  const tvDevicesData = [
    {
      id: 'tv_dev_akwa_01',
      owner_id: userMap['owner@smartads.com'].id,
      billboard_id: 'bb_akwa_001',
      name: 'Akwa Display Screen #1 (Android TV)',
      installation_id: 'inst-akwa-tv-01',
      hardware_hash: 'hw-hash-akwa-98231',
      device_metadata: JSON.stringify({ brand: 'Sony BRAVIA 4K', osVersion: 'Android 13 TV', resolution: '3840x2160' }),
      token_hash: crypto.createHash('sha256').update('device-token-akwa-01').digest('hex'),
      status: 'active',
      last_seen_at: new Date(),
      app_version: '1.0.0',
      paired_at: new Date(Date.now() - 20 * 86400000),
      created_at: new Date(Date.now() - 20 * 86400000),
    },
    {
      id: 'tv_dev_bastos_02',
      owner_id: userMap['jean@smartads.com'].id,
      billboard_id: 'bb_bastos_003',
      name: 'Bastos Mega TV Display (Xiaomi TV)',
      installation_id: 'inst-bastos-tv-02',
      hardware_hash: 'hw-hash-bastos-54123',
      device_metadata: JSON.stringify({ brand: 'Xiaomi TV Box S', osVersion: 'Android 12 TV', resolution: '1920x1080' }),
      token_hash: crypto.createHash('sha256').update('device-token-bastos-02').digest('hex'),
      status: 'active',
      last_seen_at: new Date(),
      app_version: '1.0.0',
      paired_at: new Date(Date.now() - 10 * 86400000),
      created_at: new Date(Date.now() - 10 * 86400000),
    },
  ];

  for (const tv of tvDevicesData) {
    await TvDevice.findOrCreate({
      where: { id: tv.id },
      defaults: tv,
    });
  }
  console.log(`✅ Seeded ${tvDevicesData.length} TV devices.`);

  // 4. Seed Mock Media / Video Reviews
  const sampleVideos = [
    {
      id: 'vid_rev_tech_01',
      user_id: userMap['advertiser@smartads.com'].id,
      filename: 'fotso_tech_summit_spot.mp4',
      status: 'approved',
      message: 'Video meets all broadcast safety guidelines and format specifications.',
      sha256: '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
      file_size: 1024 * 1024 * 2, // 2MB mock
    },
    {
      id: 'vid_rev_delivery_02',
      user_id: userMap['bob@smartads.com'].id,
      filename: 'express_delivery_promo.mp4',
      status: 'approved',
      message: 'Clean animation with clear branding. Approved for all audiences.',
      sha256: '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8',
      file_size: 1024 * 1024 * 3, // 3MB mock
    },
  ];

  const reviewMap = {};
  for (const v of sampleVideos) {
    const dummyPath = path.join(uploadsDir, `${v.id}.mp4`);
    if (!fs.existsSync(dummyPath)) {
      // Create lightweight dummy MP4 payload
      await fs.promises.writeFile(dummyPath, Buffer.alloc(1024, 0));
    }
    const [review] = await VideoReview.findOrCreate({
      where: { id: v.id },
      defaults: {
        id: v.id,
        user_id: v.user_id,
        filename: v.filename,
        file_path: dummyPath,
        mime_type: 'video/mp4',
        status: v.status,
        message: v.message,
        sha256: v.sha256,
        file_size: v.file_size,
        created_at: new Date(Date.now() - 5 * 86400000),
      },
    });
    reviewMap[v.id] = review;
  }
  console.log(`✅ Seeded ${Object.keys(reviewMap).length} video reviews.`);

  // 5. Seed Bookings & Payments
  const current = zonedParts();
  const todayStr = current.date; // e.g. "2026-09-25"
  
  // Create realistic upcoming and today bookings
  const bookingsData = [
    {
      id: 'bk_demo_001',
      advertiser_id: userMap['advertiser@smartads.com'].id,
      billboard_id: 'bb_akwa_001',
      review_id: 'vid_rev_tech_01',
      booking_date: todayStr,
      start_time: '18:00',
      end_time: '20:00',
      amount: 30000,
      status: 'confirmed',
      payment: {
        provider: 'MTN Mobile Money',
        amount: 30000,
      },
    },
    {
      id: 'bk_demo_002',
      advertiser_id: userMap['bob@smartads.com'].id,
      billboard_id: 'bb_bonanjo_002',
      review_id: 'vid_rev_delivery_02',
      booking_date: todayStr,
      start_time: '20:00',
      end_time: '22:00',
      amount: 36000,
      status: 'confirmed',
      payment: {
        provider: 'Orange Money',
        amount: 36000,
      },
    },
    {
      id: 'bk_demo_003',
      advertiser_id: userMap['advertiser@smartads.com'].id,
      billboard_id: 'bb_bastos_003',
      review_id: 'vid_rev_tech_01',
      booking_date: todayStr,
      start_time: '14:00',
      end_time: '16:00',
      amount: 40000,
      status: 'confirmed',
      payment: {
        provider: 'MTN Mobile Money',
        amount: 40000,
      },
    },
  ];

  for (const b of bookingsData) {
    const [booking, created] = await Booking.findOrCreate({
      where: { id: b.id },
      defaults: {
        id: b.id,
        advertiser_id: b.advertiser_id,
        billboard_id: b.billboard_id,
        review_id: b.review_id,
        booking_date: b.booking_date,
        start_time: b.start_time,
        end_time: b.end_time,
        amount: b.amount,
        status: b.status,
        schedule_revision: 1,
        created_at: new Date(Date.now() - 2 * 86400000),
        updated_at: new Date(Date.now() - 2 * 86400000),
      },
    });

    if (b.payment && (created || !(await Payment.findOne({ where: { booking_id: booking.id } })))) {
      await Payment.findOrCreate({
        where: { booking_id: booking.id },
        defaults: {
          id: `pay_${booking.id}`,
          booking_id: booking.id,
          amount: b.payment.amount,
          provider: b.payment.provider,
          status: 'paid',
          created_at: new Date(Date.now() - 2 * 86400000),
        },
      });
    }
  }
  console.log(`✅ Seeded ${bookingsData.length} bookings with confirmed simulated payments.`);

  console.log('\n✨ Database seeding completed successfully!\n');
  console.log('Available Demo Accounts:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('👑 Admin:        admin@smartads.com      /  admin1234');
  console.log('🏢 Owner 1:      owner@smartads.com      /  owner1234');
  console.log('🏢 Owner 2:      jean@smartads.com       /  owner1234');
  console.log('📢 Advertiser 1: advertiser@smartads.com /  advertiser1234');
  console.log('📢 Advertiser 2: bob@smartads.com        /  advertiser1234');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
}

if (require.main === module) {
  seed()
    .then(async () => {
      await sequelize.close();
      process.exit(0);
    })
    .catch(async (err) => {
      console.error('❌ Seeder error:', err);
      await sequelize.close();
      process.exit(1);
    });
}

module.exports = { seed };
