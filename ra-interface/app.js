/* global */
'use strict';

// ═══════════════════════════════════════════════════════════
// CONFIG & STATE
// ═══════════════════════════════════════════════════════════
const CONFIG = {
  addr:  localStorage.getItem('bao_addr')  || 'http://127.0.0.1:8200',
  token: localStorage.getItem('bao_token') || 'root',
  mount: localStorage.getItem('bao_mount') || 'pki_int',
  mountRoot: localStorage.getItem('bao_mount_root') || 'pki_root',
};

const STATE = {
  connected: false,
  currentView: 'dashboard',
  approvals: JSON.parse(localStorage.getItem('ra_approvals') || '[]'),
  auditLog:  JSON.parse(localStorage.getItem('ra_audit')    || '[]'),
  currentUser: localStorage.getItem('ra_user') || 'ra-operator',
};

// ═══════════════════════════════════════════════════════════
// OPENBAO API CLIENT
// ═══════════════════════════════════════════════════════════
const Bao = {
  async req(method, path, body) {
    const url = `${CONFIG.addr}/v1/${path}`;
    const opts = {
      method,
      headers: {
        'X-Vault-Token': CONFIG.token,
        'Content-Type': 'application/json',
      },
    };
    if (body) opts.body = JSON.stringify(body);
    const res = await fetch(url, opts);
    if (res.status === 204) return {};
    const json = await res.json();
    if (!res.ok) throw new Error(json.errors?.join(', ') || `HTTP ${res.status}`);
    return json;
  },
  get:    (p)    => Bao.req('GET',    p),
  post:   (p, b) => Bao.req('POST',   p, b),
  put:    (p, b) => Bao.req('PUT',    p, b),
  delete: (p)    => Bao.req('DELETE', p),
  list:   (p)    => Bao.req('LIST',   p),

  // PKI helpers
  async health() {
    return Bao.get('sys/health');
  },
  async listCerts() {
    try { return (await Bao.list(`${CONFIG.mount}/certs`)).data?.keys || []; }
    catch { return []; }
  },
  async readCert(serial) {
    return (await Bao.get(`${CONFIG.mount}/cert/${serial}`)).data;
  },
  async issueCert(role, payload) {
    return (await Bao.post(`${CONFIG.mount}/issue/${role}`, payload)).data;
  },
  async revokeCert(serial_number) {
    return (await Bao.post(`${CONFIG.mount}/revoke`, { serial_number })).data;
  },
  async listRoles() {
    try { return (await Bao.list(`${CONFIG.mount}/roles`)).data?.keys || []; }
    catch { return []; }
  },
  async readRole(name) {
    return (await Bao.get(`${CONFIG.mount}/roles/${name}`)).data;
  },
  async writeRole(name, payload) {
    return Bao.post(`${CONFIG.mount}/roles/${name}`, payload);
  },
  async deleteRole(name) {
    return Bao.delete(`${CONFIG.mount}/roles/${name}`);
  },
  async rootCA() {
    try { return (await Bao.get(`${CONFIG.mountRoot}/cert/ca`)).data; }
    catch { return null; }
  },
  async intCA() {
    try { return (await Bao.get(`${CONFIG.mount}/cert/ca`)).data; }
    catch { return null; }
  },
  async crl() {
    try { return (await Bao.get(`${CONFIG.mount}/cert/crl`)).data; }
    catch { return null; }
  },
  async listUsers() {
    try { return (await Bao.list('auth/userpass/users')).data?.keys || []; }
    catch { return []; }
  },
  async readUser(name) {
    try { return (await Bao.get(`auth/userpass/users/${name}`)).data; }
    catch { return null; }
  },
  async createUser(name, password, policies) {
    return Bao.post(`auth/userpass/users/${name}`, { password, policies: policies.join(',') });
  },
  async deleteUser(name) {
    return Bao.delete(`auth/userpass/users/${name}`);
  },
  async listPolicies() {
    try { return (await Bao.list('sys/policies/acl')).data?.keys || []; }
    catch { return []; }
  },
};

// ═══════════════════════════════════════════════════════════
// UTILS
// ═══════════════════════════════════════════════════════════
function daysUntil(unixTs) {
  return Math.floor((unixTs * 1000 - Date.now()) / 86400000);
}

function formatDate(unixTs) {
  if (!unixTs) return '—';
  return new Date(unixTs * 1000).toLocaleDateString('en-GB', {
    day: '2-digit', month: 'short', year: 'numeric',
  });
}

function formatDatetime(isoOrUnix) {
  const d = typeof isoOrUnix === 'number' ? new Date(isoOrUnix) : new Date(isoOrUnix);
  return d.toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
}

function expiryBadge(days) {
  if (days < 0)   return `<span class="badge badge-danger">⛔ Expired</span>`;
  if (days < 7)   return `<span class="badge badge-danger">⚠ ${days}d</span>`;
  if (days < 30)  return `<span class="badge badge-warn">⚠ ${days}d</span>`;
  return `<span class="badge badge-ok">✓ ${days}d</span>`;
}

function truncSerial(s) {
  return s ? s.substring(0, 23) + '…' : '—';
}

function uid() {
  return Math.random().toString(36).slice(2, 10).toUpperCase();
}

function auditPush(action, detail, level = 'ok') {
  STATE.auditLog.unshift({
    id: uid(), ts: new Date().toISOString(),
    user: STATE.currentUser, action, detail, level,
  });
  if (STATE.auditLog.length > 200) STATE.auditLog.length = 200;
  localStorage.setItem('ra_audit', JSON.stringify(STATE.auditLog));
}

function saveApprovals() {
  localStorage.setItem('ra_approvals', JSON.stringify(STATE.approvals));
}

function toast(msg, type = 'ok') {
  const icons = { ok: '✓', error: '✕', warn: '⚠', info: 'ℹ' };
  const el = document.createElement('div');
  el.className = `toast toast-${type}`;
  el.innerHTML = `<span>${icons[type]}</span><span>${msg}</span>`;
  document.getElementById('toast-container').appendChild(el);
  setTimeout(() => el.remove(), 4000);
}

function copyText(text) {
  navigator.clipboard.writeText(text).catch(() => {});
  toast('Copied to clipboard', 'info');
}

function showModal(id) { document.getElementById(id).classList.add('open'); }
function hideModal(id) { document.getElementById(id).classList.remove('open'); }

function el(id) { return document.getElementById(id); }

// ═══════════════════════════════════════════════════════════
// ROUTER
// ═══════════════════════════════════════════════════════════
function navigate(view) {
  STATE.currentView = view;
  document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
  const viewEl = document.getElementById(`view-${view}`);
  if (viewEl) viewEl.classList.add('active');
  const navEl = document.querySelector(`.nav-item[data-view="${view}"]`);
  if (navEl) navEl.classList.add('active');

  const titles = {
    dashboard:  ['Dashboard',              'PKI health & overview'],
    discovery:  ['Certificate Discovery',  'All issued certificates'],
    lifecycle:  ['Certificate Lifecycle',  'Issue, renew & revoke'],
    approvals:  ['Dual Approval Queue',    'Pending requests requiring 2nd operator'],
    identity:   ['Identity & Users',       'User onboarding & verification'],
    roles:      ['Roles & Policies',       'Manage PKI roles and access policies'],
    revocation: ['Revocation Monitor',     'CRL & OCSP status'],
    audit:      ['Audit Trail',            'Compliance event log'],
  };
  const [title, sub] = titles[view] || ['—', ''];
  el('topbar-title').textContent = title;
  el('topbar-sub').textContent = sub;

  modules[view]?.load?.();
}

// ═══════════════════════════════════════════════════════════
// CONNECTION
// ═══════════════════════════════════════════════════════════
async function checkConnection() {
  el('conn-dot').className  = 'status-dot connecting';
  el('conn-text').textContent = 'Connecting…';
  try {
    const h = await Bao.health();
    STATE.connected = true;
    const version = h.version || 'OpenBao';
    el('conn-dot').className   = 'status-dot connected';
    el('conn-text').textContent = `${version} — Connected`;
    el('conn-addr').textContent = CONFIG.addr;
    toast(`Connected to ${CONFIG.addr}`, 'ok');
    modules[STATE.currentView]?.load?.();
  } catch (e) {
    STATE.connected = false;
    el('conn-dot').className   = 'status-dot disconnected';
    el('conn-text').textContent = 'Disconnected';
    toast(`Cannot reach OpenBao: ${e.message}`, 'error');
  }
}

// ═══════════════════════════════════════════════════════════
// DASHBOARD MODULE
// ═══════════════════════════════════════════════════════════
const Dashboard = {
  async load() {
    el('dash-stats').innerHTML = '<div class="loading"><div class="spinner"></div> Loading…</div>';
    el('dash-ca').innerHTML    = '<div class="loading"><div class="spinner"></div></div>';

    // CA certs
    const [rootData, intData, certs, roles] = await Promise.allSettled([
      Bao.rootCA(), Bao.intCA(), Bao.listCerts(), Bao.listRoles(),
    ]);

    const root = rootData.value;
    const intC = intData.value;
    const certList = certs.value || [];
    const roleList = roles.value || [];

    // Stats
    let validCount = 0, expiringCount = 0, expiredCount = 0;
    const certDetails = [];

    for (const serial of certList.slice(0, 40)) {
      try {
        const c = await Bao.readCert(serial);
        if (c?.certificate) {
          const pem = c.certificate;
          // expiration from OpenBao response
          const expTs = c.expiration;
          if (expTs) {
            const d = daysUntil(expTs);
            certDetails.push({ serial, days: d });
            if (d < 0) expiredCount++;
            else if (d < 30) expiringCount++;
            else validCount++;
          }
        }
      } catch {}
    }

    const pendingApprovals = STATE.approvals.filter(a => a.status === 'pending').length;

    el('dash-stats').innerHTML = `
      <div class="stat-card">
        <div class="stat-label">Valid Certificates</div>
        <div class="stat-value" style="color:var(--ok)">${validCount}</div>
        <div class="stat-sub">In pki_int</div>
        <span class="stat-icon">🏅</span>
      </div>
      <div class="stat-card">
        <div class="stat-label">Expiring &lt; 30d</div>
        <div class="stat-value" style="color:var(--warn)">${expiringCount}</div>
        <div class="stat-sub">Need renewal</div>
        <span class="stat-icon">⏰</span>
      </div>
      <div class="stat-card">
        <div class="stat-label">Expired</div>
        <div class="stat-value" style="color:var(--danger)">${expiredCount}</div>
        <div class="stat-sub">Requires revocation</div>
        <span class="stat-icon">⛔</span>
      </div>
      <div class="stat-card">
        <div class="stat-label">Total Issued</div>
        <div class="stat-value">${certList.length}</div>
        <div class="stat-sub">${roleList.length} roles configured</div>
        <span class="stat-icon">📜</span>
      </div>
      <div class="stat-card" style="cursor:pointer" onclick="navigate('approvals')">
        <div class="stat-label">Pending Approvals</div>
        <div class="stat-value" style="color:var(--accent-indigo)">${pendingApprovals}</div>
        <div class="stat-sub">Awaiting 2nd operator</div>
        <span class="stat-icon">🔐</span>
      </div>
      <div class="stat-card">
        <div class="stat-label">Audit Events</div>
        <div class="stat-value">${STATE.auditLog.length}</div>
        <div class="stat-sub">${STATE.auditLog[0] ? formatDatetime(STATE.auditLog[0].ts) : 'None yet'}</div>
        <span class="stat-icon">📋</span>
      </div>
    `;

    // CA cards
    const rootDays = root?.expiration ? daysUntil(root.expiration) : null;
    const intDays  = intC?.expiration ? daysUntil(intC.expiration)  : null;

    el('dash-ca').innerHTML = `
      <div class="grid-2">
        <div class="ca-card root">
          <div class="ca-title">🔒 Root Certificate Authority</div>
          <div class="ca-name">Energy Company Root CA</div>
          ${root ? `
            <div class="ca-expiry-label">Validity remaining</div>
            <div class="ca-expiry-value" style="color:${rootDays>365?'var(--ok)':rootDays>30?'var(--warn)':'var(--danger)'}">${rootDays?.toLocaleString() ?? '?'} days</div>
            <div class="ca-expiry-date">Expires ${formatDate(root.expiration)}</div>
            <div class="progress-bar" style="margin-top:12px"><div class="progress-fill" style="width:${Math.min(100,Math.max(0,(rootDays/3650)*100))}%"></div></div>
          ` : '<div class="badge badge-danger" style="margin-top:8px">⛔ Unreachable</div>'}
        </div>
        <div class="ca-card intermediate">
          <div class="ca-title">🔗 Intermediate CA</div>
          <div class="ca-name">Energy Company K8s Intermediate CA</div>
          ${intC ? `
            <div class="ca-expiry-label">Validity remaining</div>
            <div class="ca-expiry-value" style="color:${intDays>365?'var(--ok)':intDays>30?'var(--warn)':'var(--danger)'}">${intDays?.toLocaleString() ?? '?'} days</div>
            <div class="ca-expiry-date">Expires ${formatDate(intC.expiration)}</div>
            <div class="progress-bar" style="margin-top:12px"><div class="progress-fill" style="width:${Math.min(100,Math.max(0,(intDays/1825)*100))}%;background:linear-gradient(90deg,var(--accent-indigo),var(--accent-cyan))"></div></div>
          ` : '<div class="badge badge-danger" style="margin-top:8px">⛔ Unreachable</div>'}
        </div>
      </div>
    `;

    // Expiry alert list
    const alertCerts = certDetails.filter(c => c.days < 30).sort((a,b) => a.days - b.days);
    const alertHtml = alertCerts.length
      ? alertCerts.map(c => `<tr>
          <td><span class="mono">${truncSerial(c.serial)}</span></td>
          <td>${expiryBadge(c.days)}</td>
          <td><button class="btn btn-secondary btn-sm" onclick="navigate('lifecycle')">Renew</button></td>
        </tr>`).join('')
      : `<tr><td colspan="3" style="text-align:center;color:var(--text-muted);padding:20px">✅ No certificates expiring soon</td></tr>`;

    el('dash-alerts').innerHTML = `
      <table><thead><tr><th>Serial</th><th>Expiry</th><th></th></tr></thead>
      <tbody>${alertHtml}</tbody></table>
    `;

    // Recent audit
    el('dash-audit').innerHTML = STATE.auditLog.slice(0, 5).map(e => `
      <div class="timeline-item">
        <div class="timeline-dot ${e.level}">${{ok:'✓',warn:'⚠',danger:'✕',info:'ℹ'}[e.level]||'•'}</div>
        <div class="timeline-content">
          <div class="timeline-title">${e.action}</div>
          <div class="timeline-time">${formatDatetime(e.ts)} · ${e.user}</div>
          <div class="timeline-detail">${e.detail}</div>
        </div>
      </div>
    `).join('') || '<div class="empty-state"><div class="empty-state-icon">📋</div><div class="empty-state-text">No events yet</div></div>';
  },
};

// ═══════════════════════════════════════════════════════════
// DISCOVERY MODULE
// ═══════════════════════════════════════════════════════════
const Discovery = {
  allCerts: [],
  async load() {
    el('disc-table-body').innerHTML = '<tr><td colspan="6"><div class="loading"><div class="spinner"></div> Fetching certificates…</div></td></tr>';
    const serials = await Bao.listCerts();
    const details = [];
    for (const serial of serials) {
      try {
        const c = await Bao.readCert(serial);
        if (c) details.push({ serial, ...c });
      } catch {}
    }
    this.allCerts = details;
    this.render(details);
  },
  render(certs) {
    if (!certs.length) {
      el('disc-table-body').innerHTML = '<tr><td colspan="6"><div class="empty-state"><div class="empty-state-icon">📜</div><div class="empty-state-text">No certificates found</div><div class="empty-state-sub">Issue certificates via the Lifecycle tab</div></div></td></tr>';
      return;
    }
    el('disc-table-body').innerHTML = certs.map(c => {
      const days = c.expiration ? daysUntil(c.expiration) : null;
      const subject = this._parseSubject(c.certificate);
      const revoked = c.revocation_time && c.revocation_time > 0;
      return `<tr style="cursor:pointer" onclick="Discovery.inspect('${c.serial}')">
        <td><span class="mono">${c.serial?.substring(0,29)||'—'}</span></td>
        <td style="font-weight:600">${subject.cn || '—'}</td>
        <td><span class="badge badge-indigo">${subject.ou || subject.o || '—'}</span></td>
        <td>${days !== null ? expiryBadge(days) : '—'}</td>
        <td>${formatDate(c.expiration)}</td>
        <td>
          ${revoked
            ? '<span class="badge badge-danger">Revoked</span>'
            : days < 0
              ? '<span class="badge badge-muted">Expired</span>'
              : '<span class="badge badge-ok">Active</span>'}
        </td>
      </tr>`;
    }).join('');
  },
  filter() {
    const q = el('disc-search').value.toLowerCase();
    const statusFilter = el('disc-status').value;
    const filtered = this.allCerts.filter(c => {
      const sub = this._parseSubject(c.certificate);
      const matchQ = !q || c.serial?.includes(q) || (sub.cn||'').toLowerCase().includes(q);
      const days = c.expiration ? daysUntil(c.expiration) : null;
      const revoked = c.revocation_time && c.revocation_time > 0;
      const matchStatus = !statusFilter
        || (statusFilter === 'active'   && !revoked && days >= 0)
        || (statusFilter === 'expiring' && !revoked && days >= 0 && days < 30)
        || (statusFilter === 'expired'  && days < 0)
        || (statusFilter === 'revoked'  && revoked);
      return matchQ && matchStatus;
    });
    this.render(filtered);
  },
  _parseSubject(pem) {
    if (!pem) return {};
    try {
      const lines = atob(pem.replace(/-----[^-]+-----/g,'').replace(/\s/g,'')).split('');
      return {};
    } catch {}
    const m = pem.match(/subject=([^\n]+)/);
    if (m) {
      const parts = {};
      m[1].split(',').forEach(p => {
        const [k,v] = p.trim().split('=');
        parts[k?.trim()] = v?.trim();
      });
      return { cn: parts['CN'], o: parts['O'], ou: parts['OU'] };
    }
    return {};
  },
  async inspect(serial) {
    el('inspect-serial').textContent = serial;
    el('inspect-body').innerHTML = '<div class="loading"><div class="spinner"></div></div>';
    showModal('modal-inspect');
    try {
      const c = await Bao.readCert(serial);
      const days = c.expiration ? daysUntil(c.expiration) : null;
      const revoked = c.revocation_time && c.revocation_time > 0;
      el('inspect-body').innerHTML = `
        <div class="form-group">
          <label>Status</label>
          <div style="margin-top:4px">${revoked ? '<span class="badge badge-danger">Revoked</span>' : days < 0 ? '<span class="badge badge-muted">Expired</span>' : '<span class="badge badge-ok">Active</span>'}</div>
        </div>
        <div class="form-row">
          <div class="form-group"><label>Expires</label><input type="text" readonly value="${formatDate(c.expiration)}"></div>
          <div class="form-group"><label>Days remaining</label><input type="text" readonly value="${days !== null ? days : '—'}"></div>
        </div>
        ${revoked ? `<div class="form-group"><label>Revoked at</label><input type="text" readonly value="${formatDatetime(c.revocation_time * 1000)}"></div>` : ''}
        <div class="form-group">
          <label>Certificate PEM <button class="copy-btn" onclick="copyText(\`${serial}\`)">⎘ Copy serial</button></label>
          <div class="code-block">${c.certificate || '—'}</div>
        </div>
        ${!revoked && days >= 0 ? `<button class="btn btn-danger" style="width:100%" onclick="Lifecycle.revokePrompt('${serial}');hideModal('modal-inspect')">⛔ Revoke this certificate</button>` : ''}
      `;
    } catch(e) {
      el('inspect-body').innerHTML = `<div class="empty-state"><div class="empty-state-icon">⛔</div><div class="empty-state-text">${e.message}</div></div>`;
    }
  },
};

// ═══════════════════════════════════════════════════════════
// LIFECYCLE MODULE
// ═══════════════════════════════════════════════════════════
const ROLE_TEMPLATES = {
  'smart-meter':    { allowed_domains: '*.meter.energy.internal', ttl: '720h',  alt_names: 'meter.energy.internal', key_usage: 'DigitalSignature,KeyEncipherment' },
  'scada-system':   { allowed_domains: '*.scada.energy.internal', ttl: '720h',  alt_names: 'scada.energy.internal', key_usage: 'DigitalSignature,KeyEncipherment' },
  'corporate-user': { allowed_domains: '*.corp.energy.internal',  ttl: '24h',   alt_names: '',                       key_usage: 'DigitalSignature' },
};

const Lifecycle = {
  async load() {
    const roles = await Bao.listRoles();
    const sel = el('issue-role');
    sel.innerHTML = roles.map(r => `<option value="${r}">${r}</option>`).join('');
    if (roles.length) this.applyTemplate(roles[0]);
  },
  applyTemplate(role) {
    const t = ROLE_TEMPLATES[role] || {};
    el('issue-cn').placeholder     = `e.g. device01.${(t.allowed_domains||'').replace('*.','') || 'meter.energy.internal'}`;
    el('issue-ttl').value          = t.ttl || '720h';
    el('issue-altnames').value     = t.alt_names || '';
  },
  async issue() {
    const role    = el('issue-role').value;
    const cn      = el('issue-cn').value.trim();
    const ttl     = el('issue-ttl').value.trim();
    const altnames= el('issue-altnames').value.trim();
    if (!cn) { toast('Common Name is required', 'warn'); return; }

    el('btn-issue').disabled = true;
    try {
      const payload = { common_name: cn, ttl };
      if (altnames) payload.alt_names = altnames;
      const data = await Bao.issueCert(role, payload);
      auditPush('Certificate Issued', `CN=${cn} Serial=${data.serial_number} Role=${role}`, 'ok');
      el('issued-serial').textContent = data.serial_number;
      el('issued-cert-pem').textContent = data.certificate;
      el('issued-key-pem').textContent  = data.private_key || '(key hidden — server-side generation)';
      el('tab-issued').click();
      toast(`✅ Certificate issued: ${data.serial_number}`, 'ok');
      Discovery.load();
    } catch(e) {
      toast(`Issue failed: ${e.message}`, 'error');
      auditPush('Issue Failed', `CN=${cn} Role=${role} — ${e.message}`, 'danger');
    }
    el('btn-issue').disabled = false;
  },
  revokePrompt(serial) {
    if (serial) el('revoke-serial').value = serial;
    showModal('modal-revoke');
  },
  async revoke() {
    const serial = el('revoke-serial').value.trim();
    const reason = el('revoke-reason').value;
    if (!serial) { toast('Serial number is required', 'warn'); return; }

    el('btn-revoke-confirm').disabled = true;
    try {
      await Bao.revokeCert(serial);
      auditPush('Certificate Revoked', `Serial=${serial} Reason=${reason}`, 'warn');
      hideModal('modal-revoke');
      toast(`Certificate revoked: ${serial}`, 'warn');
      Discovery.load();
    } catch(e) {
      toast(`Revoke failed: ${e.message}`, 'error');
    }
    el('btn-revoke-confirm').disabled = false;
  },
  switchTab(tab) {
    document.querySelectorAll('.issue-tab').forEach(t => t.classList.remove('active'));
    document.querySelectorAll('[data-issue-panel]').forEach(p => p.style.display = 'none');
    document.querySelector(`.issue-tab[data-panel="${tab}"]`).classList.add('active');
    const panel = document.querySelector(`[data-issue-panel="${tab}"]`);
    if (panel) panel.style.display = '';
  },
};

// ═══════════════════════════════════════════════════════════
// DUAL APPROVAL MODULE
// ═══════════════════════════════════════════════════════════
const Approvals = {
  load() {
    const pending  = STATE.approvals.filter(a => a.status === 'pending');
    const resolved = STATE.approvals.filter(a => a.status !== 'pending');

    // Update badge
    document.querySelectorAll('.approval-badge').forEach(b => {
      b.textContent = pending.length || '';
      b.style.display = pending.length ? '' : 'none';
    });

    el('approval-list').innerHTML = !STATE.approvals.length
      ? `<div class="empty-state"><div class="empty-state-icon">🔐</div><div class="empty-state-text">No approval requests</div><div class="empty-state-sub">Submit a new certificate request below</div></div>`
      : STATE.approvals.map(a => this._renderItem(a)).join('');
  },
  _renderItem(a) {
    const myRequest = a.requestedBy === STATE.currentUser;
    const isResolved = a.status !== 'pending';
    const statusClass = isResolved ? a.status : myRequest ? 'pending-my' : 'pending-other';
    const statusBadge = {
      pending:  '<span class="badge badge-warn">⏳ Pending 2nd Approval</span>',
      approved: '<span class="badge badge-ok">✓ Approved & Issued</span>',
      rejected: '<span class="badge badge-danger">✕ Rejected</span>',
    }[a.status] || '';

    return `
    <div class="approval-item ${statusClass}" id="approval-${a.id}">
      <div style="display:flex;justify-content:space-between;align-items:flex-start;flex-wrap:wrap;gap:8px">
        <div>
          <div style="font-weight:700;font-size:14px">${a.cn}</div>
          <div style="font-size:12px;color:var(--text-muted);margin-top:2px">Role: <strong>${a.role}</strong> · TTL: ${a.ttl}</div>
        </div>
        ${statusBadge}
      </div>
      <div class="approval-meta">
        <span>📋 ID: <strong>${a.id}</strong></span>
        <span>👤 Requested by: <strong>${a.requestedBy}</strong></span>
        <span>🕐 ${formatDatetime(a.ts)}</span>
        ${a.approvedBy ? `<span>✓ Approved by: <strong>${a.approvedBy}</strong></span>` : ''}
        ${a.rationale ? `<span>📝 ${a.rationale}</span>` : ''}
      </div>
      ${!isResolved && !myRequest ? `
      <div style="margin-top:12px;display:flex;gap:8px">
        <button class="btn btn-ok btn-sm" onclick="Approvals.approve('${a.id}')">✓ Approve & Issue</button>
        <button class="btn btn-danger btn-sm" onclick="Approvals.reject('${a.id}')">✕ Reject</button>
      </div>` : ''}
      ${!isResolved && myRequest ? `<div style="margin-top:10px;font-size:12px;color:var(--text-muted)">⏳ Awaiting second operator approval — you cannot self-approve</div>` : ''}
      ${a.issuedSerial ? `<div style="margin-top:10px"><span class="badge badge-ok">Serial: ${a.issuedSerial}</span></div>` : ''}
    </div>`;
  },
  submit() {
    const cn       = el('apr-cn').value.trim();
    const role     = el('apr-role').value;
    const ttl      = el('apr-ttl').value.trim();
    const altnames = el('apr-altnames').value.trim();
    const rationale= el('apr-rationale').value.trim();
    if (!cn) { toast('Common Name is required', 'warn'); return; }

    const req = {
      id: uid(), ts: new Date().toISOString(),
      cn, role, ttl, altnames, rationale,
      requestedBy: STATE.currentUser, status: 'pending',
    };
    STATE.approvals.unshift(req);
    saveApprovals();
    auditPush('Approval Request Submitted', `ID=${req.id} CN=${cn} Role=${role} by ${STATE.currentUser}`, 'info');
    toast(`Request ${req.id} submitted — awaiting 2nd operator`, 'info');
    el('apr-cn').value = el('apr-rationale').value = '';
    this.load();
    hideModal('modal-new-request');
  },
  async approve(id) {
    const req = STATE.approvals.find(a => a.id === id);
    if (!req) return;
    if (req.requestedBy === STATE.currentUser) { toast('Cannot self-approve — switch operator', 'warn'); return; }
    try {
      const payload = { common_name: req.cn, ttl: req.ttl };
      if (req.altnames) payload.alt_names = req.altnames;
      const data = await Bao.issueCert(req.role, payload);
      req.status = 'approved';
      req.approvedBy = STATE.currentUser;
      req.approvedAt = new Date().toISOString();
      req.issuedSerial = data.serial_number;
      saveApprovals();
      auditPush('Dual Approval — Certificate Issued', `ReqID=${id} CN=${req.cn} ApprovedBy=${STATE.currentUser} Serial=${data.serial_number}`, 'ok');
      toast(`✅ Approved & Issued: ${data.serial_number}`, 'ok');
      this.load();
    } catch(e) {
      toast(`Approval failed: ${e.message}`, 'error');
    }
  },
  reject(id) {
    const req = STATE.approvals.find(a => a.id === id);
    if (!req) return;
    req.status = 'rejected';
    req.approvedBy = STATE.currentUser;
    saveApprovals();
    auditPush('Dual Approval — Request Rejected', `ReqID=${id} CN=${req.cn} RejectedBy=${STATE.currentUser}`, 'warn');
    toast(`Request ${id} rejected`, 'warn');
    this.load();
  },
};

// ═══════════════════════════════════════════════════════════
// IDENTITY & USERS MODULE
// ═══════════════════════════════════════════════════════════
const Identity = {
  async load() {
    el('identity-list').innerHTML = '<div class="loading"><div class="spinner"></div> Loading users…</div>';
    const [users, policies] = await Promise.allSettled([Bao.listUsers(), Bao.listPolicies()]);

    const userList   = users.value   || [];
    const policyList = policies.value || [];

    // Populate policy dropdowns
    const policyOptions = policyList.map(p => `<option value="${p}">${p}</option>`).join('');
    el('new-user-policies').innerHTML = policyOptions;

    if (!userList.length) {
      el('identity-list').innerHTML = `<div class="empty-state"><div class="empty-state-icon">👤</div><div class="empty-state-text">No users found</div><div class="empty-state-sub">Make sure userpass auth is enabled</div></div>`;
      return;
    }

    el('identity-list').innerHTML = userList.map(u => {
      const initials = u.substring(0, 2).toUpperCase();
      const colorClass = u.includes('admin') ? 'avatar-indigo' : u.includes('team') ? 'avatar-orange' : 'avatar-cyan';
      return `
      <div class="user-row" style="border-bottom:1px solid var(--border);border-radius:0">
        <div class="avatar ${colorClass}">${initials}</div>
        <div style="flex:1">
          <div class="user-name">${u}</div>
          <div class="user-meta">userpass authentication</div>
        </div>
        <div style="display:flex;gap:6px">
          <button class="btn btn-secondary btn-sm" onclick="Identity.viewUser('${u}')">View</button>
          <button class="btn btn-danger btn-sm" onclick="Identity.deleteUser('${u}')">✕</button>
        </div>
      </div>`;
    }).join('');
  },
  async viewUser(name) {
    el('view-user-title').textContent = name;
    el('view-user-body').innerHTML = '<div class="loading"><div class="spinner"></div></div>';
    showModal('modal-view-user');
    const u = await Bao.readUser(name);
    if (!u) {
      el('view-user-body').innerHTML = '<p>Could not load user data</p>';
      return;
    }
    const pols = (u.policies || []).filter(p => p !== 'default');
    el('view-user-body').innerHTML = `
      <div class="form-group">
        <label>Policies</label>
        <div style="margin-top:6px;flex-wrap:wrap;display:flex;gap:4px">
          ${pols.length ? pols.map(p => `<span class="role-pill">🔑 ${p}</span>`).join('') : '<span class="badge badge-muted">None (beyond default)</span>'}
        </div>
      </div>
      <div class="form-group">
        <label>Token Period</label>
        <input type="text" readonly value="${u.token_period || 'none'}">
      </div>
      <div class="form-group">
        <label>Max TTL</label>
        <input type="text" readonly value="${u.token_max_ttl || 'system default'}">
      </div>
      <div class="divider"></div>
      <div style="font-size:12px;color:var(--text-muted)">
        <strong>Identity Note:</strong> To verify identity before issuing, ensure the user's policies are properly scoped to their role (smart-meter, scada-system, or corporate-user). Use OpenBao Identity entities for cross-auth-method identity linking.
      </div>
    `;
  },
  async createUser() {
    const name     = el('new-user-name').value.trim();
    const password = el('new-user-password').value.trim();
    const selected = Array.from(el('new-user-policies').selectedOptions).map(o => o.value);
    if (!name || !password) { toast('Name and password required', 'warn'); return; }

    try {
      await Bao.createUser(name, password, selected);
      auditPush('User Created', `User=${name} Policies=${selected.join(',')}`, 'ok');
      toast(`User ${name} created`, 'ok');
      hideModal('modal-new-user');
      el('new-user-name').value = el('new-user-password').value = '';
      this.load();
    } catch(e) {
      toast(`Create failed: ${e.message}`, 'error');
    }
  },
  async deleteUser(name) {
    if (!confirm(`Delete user "${name}"?`)) return;
    try {
      await Bao.deleteUser(name);
      auditPush('User Deleted', `User=${name}`, 'warn');
      toast(`User ${name} deleted`, 'warn');
      this.load();
    } catch(e) {
      toast(`Delete failed: ${e.message}`, 'error');
    }
  },
};

// ═══════════════════════════════════════════════════════════
// ROLES & POLICIES MODULE
// ═══════════════════════════════════════════════════════════
const Roles = {
  async load() {
    el('roles-list').innerHTML = '<div class="loading"><div class="spinner"></div> Loading roles…</div>';
    try {
      const names = await Bao.listRoles();
      if (!names.length) {
        el('roles-list').innerHTML = `<div class="empty-state"><div class="empty-state-icon">🔑</div><div class="empty-state-text">No roles configured</div></div>`;
        return;
      }
      const roleDetails = await Promise.allSettled(names.map(n => Bao.readRole(n)));
      el('roles-list').innerHTML = names.map((name, i) => {
        const r = roleDetails[i]?.value || {};
        return `
        <div class="card" style="margin-bottom:10px">
          <div class="card-header">
            <div class="card-title">🔑 ${name}</div>
            <div style="display:flex;gap:6px">
              <button class="btn btn-secondary btn-sm" onclick="Roles.editRole('${name}')">Edit</button>
              <button class="btn btn-danger btn-sm" onclick="Roles.deleteRole('${name}')">Delete</button>
            </div>
          </div>
          <div class="card-body">
            <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:16px;font-size:12px">
              <div><span style="color:var(--text-muted)">Allowed Domains</span><br><strong>${r.allowed_domains?.join(', ') || '—'}</strong></div>
              <div><span style="color:var(--text-muted)">Max TTL</span><br><strong>${r.max_ttl || r.ttl || '—'}</strong></div>
              <div><span style="color:var(--text-muted)">Key Type</span><br><strong>${r.key_type || 'rsa'} ${r.key_bits || 2048}</strong></div>
              <div><span style="color:var(--text-muted)">Client Auth</span><br><strong>${r.client_flag ? '✓ Yes' : '✕ No'}</strong></div>
              <div><span style="color:var(--text-muted)">Server Auth</span><br><strong>${r.server_flag ? '✓ Yes' : '✕ No'}</strong></div>
              <div><span style="color:var(--text-muted)">Subdomains</span><br><strong>${r.allow_subdomains ? '✓ Yes' : '✕ No'}</strong></div>
            </div>
          </div>
        </div>`;
      }).join('');
    } catch(e) {
      el('roles-list').innerHTML = `<div class="empty-state"><div class="empty-state-icon">⛔</div><div class="empty-state-text">${e.message}</div></div>`;
    }
  },
  async editRole(name) {
    el('role-modal-title').textContent = `Edit Role: ${name}`;
    el('role-name-input').value   = name;
    el('role-name-input').readOnly = true;
    showModal('modal-role');
    try {
      const r = await Bao.readRole(name);
      el('role-domains').value   = r.allowed_domains?.join(',') || '';
      el('role-max-ttl').value   = r.max_ttl || r.ttl || '720h';
      el('role-key-bits').value  = r.key_bits || 2048;
      el('role-client').checked  = r.client_flag ?? true;
      el('role-server').checked  = r.server_flag ?? true;
      el('role-subdomains').checked = r.allow_subdomains ?? true;
    } catch {}
  },
  newRole() {
    el('role-modal-title').textContent = 'New Role';
    el('role-name-input').value   = '';
    el('role-name-input').readOnly = false;
    el('role-domains').value = el('role-max-ttl').value = '';
    el('role-key-bits').value = 2048;
    el('role-client').checked = el('role-server').checked = el('role-subdomains').checked = true;
    showModal('modal-role');
  },
  async saveRole() {
    const name = el('role-name-input').value.trim();
    if (!name) { toast('Role name required', 'warn'); return; }
    const domains = el('role-domains').value.split(',').map(s=>s.trim()).filter(Boolean);
    const payload = {
      allowed_domains: domains,
      max_ttl:         el('role-max-ttl').value,
      key_bits:        parseInt(el('role-key-bits').value, 10),
      client_flag:     el('role-client').checked,
      server_flag:     el('role-server').checked,
      allow_subdomains:el('role-subdomains').checked,
    };
    try {
      await Bao.writeRole(name, payload);
      auditPush('Role Saved', `Role=${name} Domains=${domains.join(',')}`, 'ok');
      toast(`Role "${name}" saved`, 'ok');
      hideModal('modal-role');
      this.load();
    } catch(e) {
      toast(`Save failed: ${e.message}`, 'error');
    }
  },
  async deleteRole(name) {
    if (!confirm(`Delete role "${name}"?`)) return;
    try {
      await Bao.deleteRole(name);
      auditPush('Role Deleted', `Role=${name}`, 'warn');
      toast(`Role "${name}" deleted`, 'warn');
      this.load();
    } catch(e) {
      toast(`Delete failed: ${e.message}`, 'error');
    }
  },
};

// ═══════════════════════════════════════════════════════════
// REVOCATION MONITOR MODULE
// ═══════════════════════════════════════════════════════════
const Revocation = {
  async load() {
    el('revoc-status').innerHTML = '<div class="loading"><div class="spinner"></div></div>';
    try {
      const crl = await Bao.crl();
      el('revoc-status').innerHTML = crl ? `
        <div class="stat-card">
          <div class="stat-label">CRL Available</div>
          <div class="stat-value" style="color:var(--ok)">✓</div>
          <div class="stat-sub">pki_int/cert/crl</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">CRL Endpoint</div>
          <div class="stat-value" style="font-size:13px;font-weight:600">Active</div>
          <div class="stat-sub">${CONFIG.addr}/v1/${CONFIG.mount}/crl</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">OCSP Endpoint</div>
          <div class="stat-value" style="font-size:13px;font-weight:600">Active</div>
          <div class="stat-sub">${CONFIG.addr}/v1/${CONFIG.mount}/ocsp</div>
        </div>
      ` : `<div class="badge badge-warn">CRL not yet available — no certificates revoked</div>`;
    } catch(e) {
      el('revoc-status').innerHTML = `<span class="badge badge-danger">${e.message}</span>`;
    }

    // Revoked certs
    const serials = await Bao.listCerts();
    const revoked = [];
    for (const s of serials.slice(0, 50)) {
      try {
        const c = await Bao.readCert(s);
        if (c?.revocation_time && c.revocation_time > 0) {
          revoked.push({ serial: s, ts: c.revocation_time });
        }
      } catch {}
    }

    el('revoc-list').innerHTML = !revoked.length
      ? `<div class="empty-state"><div class="empty-state-icon">✅</div><div class="empty-state-text">No revoked certificates found</div></div>`
      : `<table><thead><tr><th>Serial</th><th>Revoked At</th><th></th></tr></thead><tbody>
          ${revoked.map(r => `<tr>
            <td><span class="mono">${r.serial}</span></td>
            <td>${formatDatetime(r.ts * 1000)}</td>
            <td><span class="badge badge-danger">Revoked</span></td>
          </tr>`).join('')}
        </tbody></table>`;
  },
};

// ═══════════════════════════════════════════════════════════
// AUDIT LOG MODULE
// ═══════════════════════════════════════════════════════════
const Audit = {
  load() {
    const log = STATE.auditLog;
    if (!log.length) {
      el('audit-timeline').innerHTML = `<div class="empty-state"><div class="empty-state-icon">📋</div><div class="empty-state-text">No events yet</div><div class="empty-state-sub">Events are recorded as you use the RA interface</div></div>`;
      return;
    }
    const icons = { ok: '✓', warn: '⚠', danger: '✕', info: 'ℹ' };
    el('audit-timeline').innerHTML = log.map(e => `
      <div class="timeline-item">
        <div class="timeline-dot ${e.level}">${icons[e.level]||'•'}</div>
        <div class="timeline-content">
          <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">
            <div class="timeline-title">${e.action}</div>
            <span class="badge badge-${e.level==='ok'?'ok':e.level==='warn'?'warn':e.level==='danger'?'danger':'info'}">${e.id}</span>
          </div>
          <div class="timeline-time">🕐 ${formatDatetime(e.ts)} · 👤 ${e.user}</div>
          <div class="timeline-detail">${e.detail}</div>
        </div>
      </div>
    `).join('');
  },
  clear() {
    if (!confirm('Clear all audit events?')) return;
    STATE.auditLog = [];
    localStorage.removeItem('ra_audit');
    this.load();
  },
  export() {
    const csv = ['Timestamp,User,Action,Detail,Level',
      ...STATE.auditLog.map(e => `"${e.ts}","${e.user}","${e.action}","${e.detail}","${e.level}"`)
    ].join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `ra_audit_${new Date().toISOString().slice(0,10)}.csv`;
    a.click();
  },
};

// ═══════════════════════════════════════════════════════════
// MODULE REGISTRY
// ═══════════════════════════════════════════════════════════
const modules = {
  dashboard:  Dashboard,
  discovery:  Discovery,
  lifecycle:  Lifecycle,
  approvals:  Approvals,
  identity:   Identity,
  roles:      Roles,
  revocation: Revocation,
  audit:      Audit,
};

// ═══════════════════════════════════════════════════════════
// SETTINGS
// ═══════════════════════════════════════════════════════════
function openSettings() {
  el('set-addr').value   = CONFIG.addr;
  el('set-token').value  = CONFIG.token;
  el('set-mount').value  = CONFIG.mount;
  el('set-user').value   = STATE.currentUser;
  showModal('modal-settings');
}

function saveSettings() {
  CONFIG.addr  = el('set-addr').value.trim();
  CONFIG.token = el('set-token').value.trim();
  CONFIG.mount = el('set-mount').value.trim();
  STATE.currentUser = el('set-user').value.trim();
  localStorage.setItem('bao_addr',  CONFIG.addr);
  localStorage.setItem('bao_token', CONFIG.token);
  localStorage.setItem('bao_mount', CONFIG.mount);
  localStorage.setItem('ra_user',   STATE.currentUser);
  el('current-user-display').textContent = STATE.currentUser;
  hideModal('modal-settings');
  checkConnection();
}

// ═══════════════════════════════════════════════════════════
// BOOTSTRAP
// ═══════════════════════════════════════════════════════════
document.addEventListener('DOMContentLoaded', () => {
  el('current-user-display').textContent = STATE.currentUser;

  // Nav clicks
  document.querySelectorAll('.nav-item[data-view]').forEach(item => {
    item.addEventListener('click', () => navigate(item.dataset.view));
  });

  // Modal close buttons
  document.querySelectorAll('.modal-close, [data-close-modal]').forEach(btn => {
    btn.addEventListener('click', () => {
      btn.closest('.modal-overlay')?.classList.remove('open');
    });
  });

  // Overlay click to close
  document.querySelectorAll('.modal-overlay').forEach(ov => {
    ov.addEventListener('click', e => { if (e.target === ov) ov.classList.remove('open'); });
  });

  // Discovery search + filter
  el('disc-search')?.addEventListener('input', () => Discovery.filter());
  el('disc-status')?.addEventListener('change', () => Discovery.filter());

  // Issue role template
  el('issue-role')?.addEventListener('change', e => Lifecycle.applyTemplate(e.target.value));

  // Populate approval modal roles
  const aprRoleSel = el('apr-role');
  Bao.listRoles().then(roles => {
    if (aprRoleSel) aprRoleSel.innerHTML = roles.map(r => `<option value="${r}">${r}</option>`).join('');
  }).catch(() => {});

  // Initial navigation
  navigate('dashboard');
  checkConnection();
});
