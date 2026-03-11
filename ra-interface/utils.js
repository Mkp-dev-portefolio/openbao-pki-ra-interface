/* utils.js — pure utility functions for the RA Console
 * Loaded as a plain <script> tag in the browser (globals available to app.js)
 * and importable via require() in Jest / Node.js test runs.
 */
'use strict';

/**
 * Number of whole days from now until a Unix timestamp.
 * Returns a negative number if the timestamp is in the past.
 * @param {number} unixTs - Unix epoch seconds
 * @returns {number}
 */
function daysUntil(unixTs) {
  return Math.floor((unixTs * 1000 - Date.now()) / 86400000);
}

/**
 * Format a Unix timestamp as a short human date (e.g. "01 Jan 2025").
 * Returns '—' for falsy input.
 * @param {number} unixTs - Unix epoch seconds
 * @returns {string}
 */
function formatDate(unixTs) {
  if (!unixTs) return '\u2014';
  return new Date(unixTs * 1000).toLocaleDateString('en-GB', {
    day: '2-digit', month: 'short', year: 'numeric',
  });
}

/**
 * Format an ISO string or millisecond timestamp as "DD Mon HH:MM".
 * @param {string|number} isoOrUnix - ISO date string or millisecond epoch
 * @returns {string}
 */
function formatDatetime(isoOrUnix) {
  const d = typeof isoOrUnix === 'number' ? new Date(isoOrUnix) : new Date(isoOrUnix);
  return d.toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
}

/**
 * Return an HTML badge string colour-coded by days remaining.
 *  < 0  → danger "Expired"
 *  < 7  → danger  "Nd"
 *  < 30 → warn    "Nd"
 *  else → ok      "Nd"
 * @param {number} days
 * @returns {string} HTML string
 */
function expiryBadge(days) {
  if (days < 0)  return '<span class="badge badge-danger">\u26d4 Expired</span>';
  if (days < 7)  return `<span class="badge badge-danger">\u26a0 ${days}d</span>`;
  if (days < 30) return `<span class="badge badge-warn">\u26a0 ${days}d</span>`;
  return `<span class="badge badge-ok">\u2713 ${days}d</span>`;
}

/**
 * Truncate a certificate serial number to 23 chars followed by an ellipsis.
 * Returns '—' for falsy input.
 * @param {string} s
 * @returns {string}
 */
function truncSerial(s) {
  return s ? s.substring(0, 23) + '\u2026' : '\u2014';
}

/**
 * Generate an 8-character random alphanumeric ID (uppercase).
 * @returns {string}
 */
function uid() {
  return Math.random().toString(36).slice(2, 10).toUpperCase();
}

/**
 * Parse the Subject fields (CN, O, OU) from a PEM certificate string.
 * OpenBao returns certificates with a text "subject=" line when read via the
 * PKI API, so this function tries to extract CN/O/OU from that line.
 * Returns an empty object if the PEM is falsy or unparseable.
 *
 * @param {string|null} pem - PEM certificate text
 * @returns {{ cn?: string, o?: string, ou?: string }}
 */
function parseSubject(pem) {
  if (!pem) return {};
  const m = pem.match(/subject=([^\n]+)/);
  if (m) {
    const parts = {};
    m[1].split(',').forEach(p => {
      const eq = p.indexOf('=');
      if (eq === -1) return;
      const k = p.slice(0, eq).trim();
      const v = p.slice(eq + 1).trim();
      parts[k] = v;
    });
    return { cn: parts['CN'], o: parts['O'], ou: parts['OU'] };
  }
  return {};
}

// ─── CommonJS export (used by Jest / Node.js) ───────────────────────────────
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { daysUntil, formatDate, formatDatetime, expiryBadge, truncSerial, uid, parseSubject };
}
