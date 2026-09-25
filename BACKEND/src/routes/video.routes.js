'use strict';
const multer = require('multer');
const router = require('express').Router();
const controller = require('../controllers/video.controller');
const { authenticate, requireRole } = require('../middleware/auth');
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 120 * 1024 * 1024, files: 1 } });
router.post('/verify', authenticate, requireRole('advertiser'), upload.single('video'), controller.verify);
module.exports = router;
