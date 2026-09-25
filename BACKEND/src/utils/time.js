'use strict';

const timezone = process.env.SMARTADS_TIMEZONE || 'Africa/Douala';

function zonedParts(timestamp = Date.now()) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: timezone,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
  }).formatToParts(new Date(timestamp));
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return { date: `${values.year}-${values.month}-${values.day}`, time: `${values.hour}:${values.minute}`, second: values.second };
}

function wallClockToEpoch(date, time) {
  const [year, month, day] = date.split('-').map(Number);
  const [hour, minute] = time.split(':').map(Number);
  const target = Date.UTC(year, month - 1, day, hour, minute, 0);
  let guess = target;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const actual = zonedParts(guess);
    const [actualYear, actualMonth, actualDay] = actual.date.split('-').map(Number);
    const [actualHour, actualMinute] = actual.time.split(':').map(Number);
    const represented = Date.UTC(actualYear, actualMonth - 1, actualDay, actualHour, actualMinute, Number(actual.second));
    guess += target - represented;
  }
  return guess;
}

module.exports = { timezone, zonedParts, wallClockToEpoch };
