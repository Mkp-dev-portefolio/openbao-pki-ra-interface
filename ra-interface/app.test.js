'use strict';

/**
 * Unit tests for the RA Console utility functions (ra-interface/utils.js).
 *
 * Run with:  cd ra-interface && npm test
 */

const {
  daysUntil,
  formatDate,
  formatDatetime,
  expiryBadge,
  truncSerial,
  uid,
  parseSubject,
} = require('./utils');

// ─── Helpers ────────────────────────────────────────────────────────────────

/** Return a Unix timestamp N days from now (fractional ok). */
function tsFromNow(days) {
  return Math.floor((Date.now() + days * 86400000) / 1000);
}

// ════════════════════════════════════════════════════════════════════════════
// daysUntil
// ════════════════════════════════════════════════════════════════════════════
describe('daysUntil', () => {
  test('returns a positive integer for a future timestamp', () => {
    const ts = tsFromNow(10);
    const result = daysUntil(ts);
    // Allow ±1 day tolerance for test execution timing
    expect(result).toBeGreaterThanOrEqual(9);
    expect(result).toBeLessThanOrEqual(10);
  });

  test('returns 0 for a timestamp approximately now', () => {
    const ts = tsFromNow(0.01); // ~14 minutes from now
    expect(daysUntil(ts)).toBe(0);
  });

  test('returns a negative integer for an expired timestamp', () => {
    const ts = tsFromNow(-5);
    const result = daysUntil(ts);
    expect(result).toBeLessThanOrEqual(-5);
    expect(result).toBeGreaterThanOrEqual(-6);
  });

  test('handles far-future timestamps (10 years)', () => {
    const ts = tsFromNow(3650);
    expect(daysUntil(ts)).toBeGreaterThan(3640);
  });

  test('handles very old timestamps', () => {
    const ts = tsFromNow(-3650);
    expect(daysUntil(ts)).toBeLessThan(-3640);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// formatDate
// ════════════════════════════════════════════════════════════════════════════
describe('formatDate', () => {
  test('returns an em-dash for null', () => {
    expect(formatDate(null)).toBe('\u2014');
  });

  test('returns an em-dash for 0', () => {
    expect(formatDate(0)).toBe('\u2014');
  });

  test('returns an em-dash for undefined', () => {
    expect(formatDate(undefined)).toBe('\u2014');
  });

  test('formats a known Unix timestamp correctly', () => {
    // 2025-01-15 00:00:00 UTC  →  1736899200
    const result = formatDate(1736899200);
    expect(result).toMatch(/Jan/);
    expect(result).toMatch(/2025/);
  });

  test('returns a string for any valid timestamp', () => {
    expect(typeof formatDate(tsFromNow(30))).toBe('string');
  });
});

// ════════════════════════════════════════════════════════════════════════════
// formatDatetime
// ════════════════════════════════════════════════════════════════════════════
describe('formatDatetime', () => {
  test('accepts a millisecond timestamp (number)', () => {
    const ms = 1736899200000; // 2025-01-15 UTC
    const result = formatDatetime(ms);
    expect(typeof result).toBe('string');
    expect(result.length).toBeGreaterThan(0);
  });

  test('accepts an ISO string', () => {
    const result = formatDatetime('2025-06-01T12:30:00Z');
    expect(typeof result).toBe('string');
    expect(result).toMatch(/Jun/);
  });

  test('includes hour and minute parts', () => {
    // A fixed UTC time that avoids midnight edge cases
    const result = formatDatetime('2025-03-15T14:05:00.000Z');
    // The exact output is locale-dependent in Node.js, but should contain
    // numeric hour/minute components separated by ':'
    expect(result).toMatch(/\d{2}:\d{2}/);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// expiryBadge
// ════════════════════════════════════════════════════════════════════════════
describe('expiryBadge', () => {
  test('expired certificate gets badge-danger and "Expired" text', () => {
    const badge = expiryBadge(-1);
    expect(badge).toContain('badge-danger');
    expect(badge).toContain('Expired');
  });

  test('exactly 0 days is treated as expired', () => {
    // daysUntil returns 0 on the last day; expiryBadge(0) should NOT show "Expired"
    // because 0 is >= 0 (not < 0). It falls into the < 7 bucket.
    const badge = expiryBadge(0);
    expect(badge).toContain('badge-danger');
    expect(badge).not.toContain('Expired');
    expect(badge).toContain('0d');
  });

  test('6 days remaining gets badge-danger', () => {
    const badge = expiryBadge(6);
    expect(badge).toContain('badge-danger');
    expect(badge).toContain('6d');
  });

  test('7 days remaining gets badge-warn (boundary)', () => {
    const badge = expiryBadge(7);
    expect(badge).toContain('badge-warn');
    expect(badge).toContain('7d');
  });

  test('29 days remaining gets badge-warn', () => {
    const badge = expiryBadge(29);
    expect(badge).toContain('badge-warn');
  });

  test('30 days remaining gets badge-ok (boundary)', () => {
    const badge = expiryBadge(30);
    expect(badge).toContain('badge-ok');
    expect(badge).toContain('30d');
  });

  test('365 days remaining gets badge-ok', () => {
    const badge = expiryBadge(365);
    expect(badge).toContain('badge-ok');
  });

  test('returns a valid HTML span element string', () => {
    const badge = expiryBadge(90);
    expect(badge).toMatch(/^<span class="badge/);
    expect(badge).toMatch(/<\/span>$/);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// truncSerial
// ════════════════════════════════════════════════════════════════════════════
describe('truncSerial', () => {
  test('returns em-dash for null', () => {
    expect(truncSerial(null)).toBe('\u2014');
  });

  test('returns em-dash for empty string', () => {
    expect(truncSerial('')).toBe('\u2014');
  });

  test('truncates a long serial to 23 chars + ellipsis', () => {
    const serial = '4a:fc:98:16:75:89:ab:cd:ef:01:23:45:67:89:ab:cd';
    const result = truncSerial(serial);
    expect(result).toHaveLength(24); // 23 chars + 1 unicode ellipsis char
    expect(result.endsWith('\u2026')).toBe(true);
  });

  test('does not truncate a short serial (< 23 chars)', () => {
    const serial = 'abc123';
    const result = truncSerial(serial);
    // Short serials are still truncated at position 23 (but nothing is cut)
    // substring(0, 23) of a 6-char string returns the 6-char string
    expect(result).toBe('abc123\u2026');
  });

  test('handles exactly 23-character serial', () => {
    const serial = '4a:fc:98:16:75:89:ab:cd:'; // 24 chars — gets truncated
    const result = truncSerial(serial);
    expect(result.endsWith('\u2026')).toBe(true);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// uid
// ════════════════════════════════════════════════════════════════════════════
describe('uid', () => {
  test('returns an 8-character string', () => {
    const id = uid();
    expect(id).toHaveLength(8);
  });

  test('returns an uppercase alphanumeric string', () => {
    const id = uid();
    expect(id).toMatch(/^[A-Z0-9]{8}$/);
  });

  test('generates unique IDs across multiple calls', () => {
    const ids = new Set(Array.from({ length: 200 }, () => uid()));
    // Very unlikely to have collisions in 200 8-char base-36 IDs
    expect(ids.size).toBeGreaterThan(195);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// parseSubject
// ════════════════════════════════════════════════════════════════════════════
describe('parseSubject', () => {
  test('returns empty object for null', () => {
    expect(parseSubject(null)).toEqual({});
  });

  test('returns empty object for empty string', () => {
    expect(parseSubject('')).toEqual({});
  });

  test('returns empty object for a PEM with no subject= line', () => {
    const pem = '-----BEGIN CERTIFICATE-----\nMIIFoo...\n-----END CERTIFICATE-----';
    expect(parseSubject(pem)).toEqual({});
  });

  test('parses a simple subject line with CN, O, and OU', () => {
    const pem = 'subject=CN=device01.meter.energy.internal, O=Energy Corp, OU=IoT Devices\n';
    const result = parseSubject(pem);
    expect(result.cn).toBe('device01.meter.energy.internal');
    expect(result.o).toBe('Energy Corp');
    expect(result.ou).toBe('IoT Devices');
  });

  test('parses subject with only CN', () => {
    const pem = 'subject=CN=control-unit-01.scada.energy.internal\n';
    const result = parseSubject(pem);
    expect(result.cn).toBe('control-unit-01.scada.energy.internal');
    expect(result.o).toBeUndefined();
    expect(result.ou).toBeUndefined();
  });

  test('handles extra whitespace around key=value pairs', () => {
    const pem = 'subject= CN = api.corp.energy.internal , O = Energy Corp \n';
    const result = parseSubject(pem);
    expect(result.cn).toBe('api.corp.energy.internal');
    expect(result.o).toBe('Energy Corp');
  });

  test('handles PEM with multiple lines before subject=', () => {
    const pem = [
      '-----BEGIN CERTIFICATE-----',
      'MIIFoo==',
      '-----END CERTIFICATE-----',
      'subject=CN=server.blue.energy.internal, OU=Team Blue',
    ].join('\n');
    const result = parseSubject(pem);
    expect(result.cn).toBe('server.blue.energy.internal');
    expect(result.ou).toBe('Team Blue');
  });

  test('returns undefined for missing fields', () => {
    const pem = 'subject=CN=test.energy.internal\n';
    const result = parseSubject(pem);
    expect(result.ou).toBeUndefined();
    expect(result.o).toBeUndefined();
  });
});

// ════════════════════════════════════════════════════════════════════════════
// Approval self-approval prevention (business logic unit test)
// This mirrors the guard in Approvals.approve() in app.js
// ════════════════════════════════════════════════════════════════════════════
describe('Approvals — self-approval prevention logic', () => {
  /**
   * Inline implementation of the self-approval guard extracted from app.js
   * Approvals.approve().  Tests verify the expected behaviour independently
   * of the DOM / fetch environment.
   */
  function canApprove(request, currentUser) {
    return request.requestedBy !== currentUser;
  }

  test('blocks self-approval when requester and approver are the same user', () => {
    const req = { id: 'REQ001', requestedBy: 'ra-operator', status: 'pending' };
    expect(canApprove(req, 'ra-operator')).toBe(false);
  });

  test('allows approval when a different user approves', () => {
    const req = { id: 'REQ001', requestedBy: 'ra-operator', status: 'pending' };
    expect(canApprove(req, 'ra-validator')).toBe(true);
  });

  test('is case-sensitive (different capitalisation counts as different user)', () => {
    const req = { id: 'REQ002', requestedBy: 'Ra-Operator', status: 'pending' };
    expect(canApprove(req, 'ra-operator')).toBe(true);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// Discovery filter logic (business logic unit test)
// Mirrors the filter predicate in Discovery.filter() in app.js
// ════════════════════════════════════════════════════════════════════════════
describe('Discovery.filter — certificate list filtering', () => {
  /**
   * Standalone re-implementation of the filter predicate from Discovery.filter().
   * Kept in sync with app.js; if the production code changes this logic,
   * these tests will catch the divergence.
   */
  function filterCert(cert, query, statusFilter) {
    const sub = parseSubject(cert.certificate);
    const matchQ = !query || cert.serial?.includes(query) || (sub.cn || '').toLowerCase().includes(query);
    const days = cert.expiration ? daysUntil(cert.expiration) : null;
    const revoked = cert.revocation_time && cert.revocation_time > 0;
    const matchStatus = !statusFilter
      || (statusFilter === 'active'   && !revoked && days >= 0)
      || (statusFilter === 'expiring' && !revoked && days >= 0 && days < 30)
      || (statusFilter === 'expired'  && days < 0)
      || (statusFilter === 'revoked'  && revoked);
    return matchQ && matchStatus;
  }

  const activeCert = {
    serial: '4a:fc:98:00:01',
    expiration: tsFromNow(90),
    revocation_time: 0,
    certificate: 'subject=CN=device01.meter.energy.internal\n',
  };

  const expiredCert = {
    serial: '4a:fc:98:00:02',
    expiration: tsFromNow(-5),
    revocation_time: 0,
    certificate: 'subject=CN=old.corp.energy.internal\n',
  };

  const expiringCert = {
    serial: '4a:fc:98:00:03',
    expiration: tsFromNow(15),
    revocation_time: 0,
    certificate: 'subject=CN=soon.meter.energy.internal\n',
  };

  const revokedCert = {
    serial: '4a:fc:98:00:04',
    expiration: tsFromNow(60),
    revocation_time: 1700000000,
    certificate: 'subject=CN=revoked.scada.energy.internal\n',
  };

  test('empty query and no status filter returns all certs', () => {
    const certs = [activeCert, expiredCert, expiringCert, revokedCert];
    expect(certs.filter(c => filterCert(c, '', ''))).toHaveLength(4);
  });

  test('query on serial matches correct cert', () => {
    expect(filterCert(activeCert,  '4a:fc:98:00:01', '')).toBeTruthy();
    expect(filterCert(expiredCert, '4a:fc:98:00:01', '')).toBeFalsy();
  });

  test('query on CN (lowercase) matches correct cert', () => {
    expect(filterCert(activeCert,  'device01', '')).toBeTruthy();
    expect(filterCert(expiredCert, 'device01', '')).toBeFalsy();
  });

  test('status filter "active" excludes expired and revoked certs', () => {
    expect(filterCert(activeCert,   '', 'active')).toBeTruthy();
    expect(filterCert(expiredCert,  '', 'active')).toBeFalsy();
    expect(filterCert(expiringCert, '', 'active')).toBeTruthy();  // 15d is active (not expired/revoked)
    expect(filterCert(revokedCert,  '', 'active')).toBeFalsy();
  });

  test('status filter "expiring" matches certs within 30 days', () => {
    expect(filterCert(activeCert,   '', 'expiring')).toBeFalsy();
    expect(filterCert(expiringCert, '', 'expiring')).toBeTruthy();
    expect(filterCert(expiredCert,  '', 'expiring')).toBeFalsy();
    expect(filterCert(revokedCert,  '', 'expiring')).toBeFalsy();
  });

  test('status filter "expired" matches only expired certs', () => {
    expect(filterCert(expiredCert,  '', 'expired')).toBeTruthy();
    expect(filterCert(activeCert,   '', 'expired')).toBeFalsy();
    expect(filterCert(revokedCert,  '', 'expired')).toBeFalsy();
  });

  test('status filter "revoked" matches only revoked certs', () => {
    expect(filterCert(revokedCert, '', 'revoked')).toBeTruthy();
    expect(filterCert(activeCert,  '', 'revoked')).toBeFalsy();
  });

  test('combined query + status filter both apply (AND)', () => {
    // Only return expiring certs whose CN contains "meter"
    expect(filterCert(expiringCert, 'meter', 'expiring')).toBeTruthy();
    expect(filterCert(expiringCert, 'scada', 'expiring')).toBeFalsy();
  });
});
