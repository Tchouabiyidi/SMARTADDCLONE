'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { VideoReview } = require('../models');
const { verifyVideo } = require('../services/gemini.service');
const { fail } = require('../utils/errors');

const uploadDir = path.join(__dirname, '..', '..', 'uploads');
fs.mkdirSync(uploadDir, { recursive: true });

function validateDuration(filePath) {
  let output;
  try {
    output = execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', filePath], { encoding: 'utf8', timeout: 10000, stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    // ffprobe is not installed or failed to probe; allow video without strict ffprobe requirement
    return;
  }
  const duration = Number(output);
  if (duration > 180) throw fail(413, 'Video must be 3 minutes or shorter. Trim it and try again.');
}

async function verify(req, res) {
  if (!req.file?.buffer?.length) throw fail(400, 'No video file was included.');
  const extension = path.extname(req.file.originalname).toLowerCase();
  const allowedExtensions = ['.mp4', '.mov', '.webm', '.m4v', '.mkv', '.avi'];
  const isAllowedExt = allowedExtensions.includes(extension);
  const isVideoMime = (req.file.mimetype && req.file.mimetype.startsWith('video/')) || req.file.mimetype === 'application/octet-stream';
  if (!isAllowedExt && !isVideoMime) throw fail(415, 'Choose an MP4, MOV, M4V, or WebM video.');

  const mimeType = (req.file.mimetype === 'application/octet-stream' || !req.file.mimetype)
    ? (extension === '.webm' ? 'video/webm' : extension === '.mov' ? 'video/quicktime' : 'video/mp4')
    : req.file.mimetype;

  const reviewId = crypto.randomUUID();
  const filePath = path.join(uploadDir, `${reviewId}${extension || '.mp4'}`);
  await fs.promises.writeFile(filePath, req.file.buffer, { flag: 'wx' });
  try {
    validateDuration(filePath);
    const assessment = await verifyVideo(filePath, mimeType);
    const status = assessment.approved ? 'approved' : 'rejected';
    const review = await VideoReview.create({
      id: reviewId, user_id: req.user.id, filename: req.file.originalname, file_path: filePath,
      mime_type: mimeType, status, message: assessment.message,
      sha256: crypto.createHash('sha256').update(req.file.buffer).digest('hex'),
      file_size: req.file.buffer.length, created_at: new Date(),
    });
    res.status(assessment.approved ? 201 : 422).json(assessment.approved
      ? { review: { id: review.id, filename: review.filename, status, message: review.message } }
      : { error: assessment.message, review: { id: review.id, filename: review.filename, status, message: review.message } });
  } catch (error) {
    await fs.promises.unlink(filePath).catch(() => {});
    throw error;
  }
}

module.exports = { verify };
