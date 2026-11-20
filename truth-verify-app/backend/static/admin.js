const $ = (id) => document.getElementById(id);
let token = localStorage.getItem('tl_token') || '';
let cachedOverview = null;

function esc(str) {
  return String(str ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

async function api(path, opts = {}) {
  const headers = {
    'Content-Type': 'application/json',
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
    ...(opts.headers || {}),
  };
  const res = await fetch(path, { ...opts, headers });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.detail || `Error ${res.status}`);
  return data;
}

document.querySelectorAll('.tab-btn').forEach((btn) => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.tab-btn').forEach((b) => b.classList.remove('active'));
    btn.classList.add('active');
    const tab = btn.dataset.tab;
    ['users', 'recharges', 'settings', 'scans', 'alerts'].forEach((id) => {
      $(`tab-${id}`).classList.toggle('hidden', id !== tab);
    });
  });
});

$('admin-login-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const errEl = $('login-err');
  errEl.classList.add('hidden');
  try {
    const res = await api('/api/auth/dev-login', {
      method: 'POST',
      body: JSON.stringify({
        email: $('login-email').value.trim(),
        name: 'Admin',
        password: $('login-pass').value,
      }),
    });
    if (!res.user || !res.user.is_admin) {
      throw new Error('This account does not have Admin permissions. Check ADMIN_EMAILS & ADMIN_PASSWORD.');
    }
    token = res.token;
    localStorage.setItem('tl_token', token);
    await loadOverview();
  } catch (err) {
    errEl.textContent = err.message;
    errEl.classList.remove('hidden');
  }
});

$('btn-logout').addEventListener('click', () => {
  token = '';
  localStorage.removeItem('tl_token');
  $('admin-body').classList.add('hidden');
  $('btn-refresh').classList.add('hidden');
  $('btn-logout').classList.add('hidden');
  $('login-box').classList.remove('hidden');
});

$('btn-refresh').addEventListener('click', () => loadOverview());
$('user-search').addEventListener('input', () => renderUsers());

function renderUsers() {
  if (!cachedOverview) return;
  const q = ($('user-search').value || '').trim().toLowerCase();
  const list = (cachedOverview.users || []).filter(
    (u) => !q || (u.email || '').toLowerCase().includes(q) || (u.name || '').toLowerCase().includes(q),
  );
  const usersBody = $('users-tbody');
  if (!list.length) {
    usersBody.innerHTML = '<tr><td colspan="5" style="color:var(--muted)">No matching users found.</td></tr>';
    return;
  }
  usersBody.innerHTML = list
    .map(
      (u) => `
    <tr>
      <td>
        <div style="font-weight:600">${esc(u.name || u.email)}</div>
        <div style="font-size:12px;color:var(--muted)">${esc(u.email)}</div>
        <div style="margin-top:4px;display:flex;gap:6px;flex-wrap:wrap">
          ${u.google_connected ? '<span class="pill pill-cyan">Google</span>' : '<span class="pill pill-purple">Email</span>'}
          ${u.is_admin ? '<span class="pill pill-purple">ADMIN</span>' : ''}
        </div>
      </td>
      <td style="font-weight:700;color:var(--good)">₹${Number(u.wallet_balance || 0).toFixed(0)}</td>
      <td>${u.total_questions_asked} <span style="color:var(--muted);font-size:11px">(Free: ${u.free_questions_used})</span></td>
      <td>${u.is_banned ? '<span class="pill pill-bad">Blocked</span>' : '<span class="pill pill-good">Active</span>'}</td>
      <td>
        <div class="wallet-inline">
          <input class="wallet-amt" type="number" id="amt-${esc(u.id)}" value="50" min="1" />
          <button class="ok-btn" style="padding:6px 9px;font-size:12px" data-uid="${esc(u.id)}" data-sign="1">+Add</button>
          <button class="ghost" style="padding:6px 9px;font-size:12px" data-uid="${esc(u.id)}" data-sign="-1">-Deduct</button>
          <button class="danger-ghost" style="padding:6px 9px;font-size:12px" data-ban="${esc(u.id)}">${u.is_banned ? 'Unblock' : 'Block'}</button>
        </div>
      </td>
    </tr>`,
    )
    .join('');

  usersBody.querySelectorAll('button[data-uid]').forEach((b) => {
    b.addEventListener('click', async () => {
      const uid = b.dataset.uid;
      const sign = Number(b.dataset.sign || '1');
      const amtInput = document.getElementById(`amt-${uid}`);
      const amount = Math.max(1, Number(amtInput ? amtInput.value : 50) || 50);
      await api(`/api/admin/users/${uid}/wallet`, {
        method: 'POST',
        body: JSON.stringify({ delta: sign * amount }),
      });
      loadOverview();
    });
  });

  usersBody.querySelectorAll('button[data-ban]').forEach((b) => {
    b.addEventListener('click', async () => {
      await api(`/api/admin/users/${b.dataset.ban}/toggle-ban`, { method: 'POST' });
      loadOverview();
    });
  });
}

async function loadOverview() {
  if (!token) {
    $('login-box').classList.remove('hidden');
    $('admin-body').classList.add('hidden');
    return;
  }
  try {
    const data = await api('/api/admin/overview');
    cachedOverview = data;
    $('login-box').classList.add('hidden');
    $('admin-body').classList.remove('hidden');
    $('btn-refresh').classList.remove('hidden');
    $('btn-logout').classList.remove('hidden');

    $('st-users').textContent = data.stats.total_users ?? 0;
    $('st-scans').textContent = data.stats.total_scans ?? data.stats.total_questions ?? 0;
    $('st-rev').textContent = `₹${Number(data.stats.total_revenue || 0).toLocaleString('en-IN')}`;
    $('st-wallets').textContent = `₹${Number(data.stats.active_wallet_balances || 0).toLocaleString('en-IN')}`;
    $('st-rec').textContent = data.stats.pending_recharges ?? 0;
    $('st-alerts').textContent = data.stats.flagged_alerts ?? 0;

    // Pricing settings
    $('set-price').value = data.settings.price_per_question;
    $('set-minrec').value = data.settings.min_recharge;
    $('set-free').value = data.settings.free_questions;
    $('set-upi').value = data.settings.upi_id;

    // OTA Config
    const ota = data.ota_config || {};
    $('ota-version').value = ota.app_version || '4.0.0';
    $('ota-maint').value = ota.maintenance_message || '';
    $('ota-questions').value = (ota.baseline_questions || []).join('\n');
    const dets = ota.active_detectors || {};
    $('ota-detectors').innerHTML = Object.entries(dets)
      .map(
        ([k, v]) => `
      <label class="toggle-item">
        <span>${esc(k.replace(/_/g, ' '))}</span>
        <input type="checkbox" data-det="${esc(k)}" ${v ? 'checked' : ''} />
      </label>`,
      )
      .join('');

    renderUsers();

    // Recharges
    const recBody = $('recharges-tbody');
    recBody.innerHTML = (data.recharges || []).length
      ? data.recharges
          .map(
            (r) => `
        <tr>
          <td>${esc(r.user_email)}</td>
          <td style="font-weight:700;color:var(--good)">₹${r.amount}</td>
          <td style="font-family:monospace">${esc(r.utr)}</td>
          <td><span class="pill ${r.status === 'approved' ? 'pill-good' : r.status === 'rejected' ? 'pill-bad' : 'pill-warn'}">${esc(r.status)}</span></td>
          <td>
            ${
              r.status === 'pending'
                ? `<button class="ok-btn" style="padding:6px 10px;font-size:12px" data-rec="${esc(r.id)}" data-act="approve">Approve</button>
                   <button class="danger-ghost" style="padding:6px 10px;font-size:12px" data-rec="${esc(r.id)}" data-act="reject">Reject</button>`
                : '<span style="color:var(--muted);font-size:12px">Done</span>'
            }
          </td>
        </tr>`,
          )
          .join('')
      : '<tr><td colspan="5" style="color:var(--muted)">No recharge requests yet.</td></tr>';

    recBody.querySelectorAll('button[data-rec]').forEach((b) => {
      b.addEventListener('click', async () => {
        await api(`/api/admin/recharges/${b.dataset.rec}/${b.dataset.act}`, { method: 'POST' });
        loadOverview();
      });
    });

    // Recent Scans
    const scansBody = $('scans-tbody');
    scansBody.innerHTML = (data.recent_scans || []).length
      ? data.recent_scans
          .map(
            (s) => `
        <tr>
          <td>${esc(s.user_email)}</td>
          <td>${esc(s.question || s.title)}</td>
          <td><span class="pill ${s.consistency_score >= 70 ? 'pill-good' : s.consistency_score >= 45 ? 'pill-warn' : 'pill-bad'}">${s.consistency_score}%</span></td>
          <td style="max-width:340px;font-size:12px">${esc(s.verdict)}</td>
          <td style="color:var(--muted);font-size:12px">${new Date(s.created_at).toLocaleString()}</td>
        </tr>`,
          )
          .join('')
      : '<tr><td colspan="5" style="color:var(--muted)">No scans recorded yet.</td></tr>';

    // Flagged videos
    const alertsEl = $('alerts-list');
    alertsEl.innerHTML = (data.alerts || []).length
      ? data.alerts
          .map(
            (a) => `
        <div class="alert-card">
          <div><b>User:</b> ${esc(a.user_email)} · <span class="sub">${new Date(a.created_at).toLocaleString()}</span></div>
          <div style="margin-top:6px"><b>Question:</b> ${esc(a.question_text)}</div>
          <div style="margin-top:6px;color:#fda4af"><b>Keywords:</b> ${esc((a.matched_keywords || []).join(', '))}</div>
          ${a.video_url ? `<video controls src="${esc(a.video_url)}"></video>` : '<p class="sub">No video clip attached</p>'}
        </div>`,
          )
          .join('')
      : '<p class="sub">No flagged unsafe videos recorded.</p>';
  } catch (err) {
    token = '';
    localStorage.removeItem('tl_token');
    $('login-box').classList.remove('hidden');
    $('admin-body').classList.add('hidden');
    $('login-err').textContent = err.message;
    $('login-err').classList.remove('hidden');
  }
}

$('btn-save-settings').addEventListener('click', async () => {
  const msg = $('set-msg');
  msg.classList.add('hidden');
  try {
    await api('/api/admin/settings', {
      method: 'POST',
      body: JSON.stringify({
        price_per_question: Number($('set-price').value),
        min_recharge: Number($('set-minrec').value),
        free_questions: Number($('set-free').value),
        upi_id: $('set-upi').value.trim(),
      }),
    });
    msg.textContent = 'Pricing & UPI updated live across all apps!';
    msg.classList.remove('hidden');
  } catch (err) {
    msg.textContent = err.message;
    msg.classList.remove('hidden');
  }
});

$('btn-save-ota').addEventListener('click', async () => {
  const msg = $('ota-msg');
  msg.classList.add('hidden');
  try {
    const detectors = {};
    document.querySelectorAll('input[data-det]').forEach((el) => {
      detectors[el.dataset.det] = el.checked;
    });
    const questions = $('ota-questions')
      .value.split('\n')
      .map((s) => s.trim())
      .filter(Boolean);
    await api('/api/admin/ota-config', {
      method: 'POST',
      body: JSON.stringify({
        app_version: $('ota-version').value.trim() || '4.0.0',
        maintenance_message: $('ota-maint').value.trim(),
        baseline_questions: questions,
        active_detectors: detectors,
      }),
    });
    msg.textContent = 'OTA config pushed live to mobile apps (no APK rebuild needed)!';
    msg.classList.remove('hidden');
  } catch (err) {
    msg.textContent = err.message;
    msg.classList.remove('hidden');
  }
});

loadOverview();
