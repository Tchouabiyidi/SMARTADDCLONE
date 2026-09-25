'use strict';

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const fail = (status, message) => new HttpError(status, message);

module.exports = { HttpError, fail };
