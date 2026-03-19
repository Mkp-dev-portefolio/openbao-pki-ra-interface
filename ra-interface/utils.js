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
 * Returns '\u2014' for falsy input.
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
 *  < 0  -> danger "Expired"
 *  < 7  -> danger  "Nd"
 *  < 30 -> warn    "Nd"
 *  else -> ok      "Nd"
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
 * Returns '\u2014' for falsy input.
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

/**
 * Decode a PEM certificate and extract basic fields.
 * Works with the text representation OpenBao returns.
 * @param {string} pem
 * @returns {{ issuer?: string, serial?: string, notBefore?: string, notAfter?: string, cn?: string }}
 */
function decodePEM(pem) {
  if (!pem) return {};
  const result = {};
  const issuerMatch = pem.match(/issuer=([^\n]+)/);
  if (issuerMatch) result.issuer = issuerMatch[1].trim();
  const subj = parseSubject(pem);
  if (subj.cn) result.cn = subj.cn;
  return result;
}

/**
 * Format seconds into a human-readable duration string.
 * @param {number} seconds
 * @returns {string}
 */
function formatDuration(seconds) {
  if (!seconds || seconds <= 0) return '0s';
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

/**
 * Fuzzy match a query against a string (case-insensitive).
 * Supports space-separated terms (AND logic).
 * @param {string} text - Text to search in
 * @param {string} query - Search query
 * @returns {boolean}
 */
function fuzzyMatch(text, query) {
  if (!query) return true;
  const lower = (text || '').toLowerCase();
  return query.toLowerCase().split(/\s+/).every(term => lower.includes(term));
}

/**
 * Debounce a function call.
 * @param {Function} fn
 * @param {number} ms
 * @returns {Function}
 */
function debounce(fn, ms) {
  let timer;
  return function(...args) {
    clearTimeout(timer);
    timer = setTimeout(() => fn.apply(this, args), ms);
  };
}

/**
 * Animate a numeric value from start to end.
 * @param {HTMLElement} el - Element to update
 * @param {number} start
 * @param {number} end
 * @param {number} duration - Animation duration in ms
 */
function animateCounter(el, start, end, duration) {
  if (typeof document === 'undefined') return;
  const startTime = performance.now();
  const diff = end - start;
  function step(now) {
    const elapsed = now - startTime;
    const progress = Math.min(elapsed / duration, 1);
    const eased = 1 - Math.pow(1 - progress, 3);
    el.textContent = Math.round(start + diff * eased);
    if (progress < 1) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
}

// CommonJS export (used by Jest / Node.js)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { daysUntil, formatDate, formatDatetime, expiryBadge, truncSerial, uid, parseSubject, decodePEM, formatDuration, fuzzyMatch, debounce, animateCounter };
}
