'use strict';
const router = require('express').Router();
const controller = require('../controllers/auth.controller');
const { authenticate } = require('../middleware/auth');
router.post('/signup', controller.signup);
router.post('/login', controller.login);
router.get('/me', authenticate, controller.me);
module.exports = router;
