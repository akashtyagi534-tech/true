const $ = (id) => document.getElementById(id);
const token = localStorage.getItem('tl_token') || '';

async function api(path, opts = {}) {
  const headers = {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${token}`,
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
    ['alerts', 'recharges', 'settings', 'users'].forEach((id) => {
      $(`tab-${id}`).classList.toggle('hidden', id !== tab);
    });
  });
});

async function loadOverview() {
  if (!token) {
    $('admin-err').classList.remove('hidden');
    $('admin-err-text').textContent = 'Pehle main page par Admin email se login karein.';
    return;
  }
  try {
    const data = await api('/api/admin/overview');
    $('admin-body').classList.remove('hidden');
    $('st-rev').textContent = `₹${data.stats.total_revenue}`;
    $('st-users').textContent = data.stats.total_users;
    $('st-qs').textContent = data.stats.total_questions;
    $('st-rec').textContent = data.stats.pending_recharges;
    $('st-alerts').textContent = data.stats.flagged_alerts;

    // Settings
    $('set-price').value = data.settings.price_per_question;
    $('set-minrec').value = data.settings.min_recharge;
    $('set-free').value = data.settings.free_questions;
    $('set-upi').value = data.settings.upi_id;

    // Flagged videos
    const alertsEl = $('alerts-list');
    alertsEl.innerHTML = data.alerts.length
      ? data.alerts
          .map(
            (a) => `
        <div class="alert-card">
          <div><b>User:</b> ${a.user_email} · <span class="sub">${new Date(a.created_at).toLocaleString()}</span></div>
          <div style="margin-top:4px"><b>Question:</b> ${a.question_text}</div>
          <div style="margin-top:4px;color:#fca5a5"><b>Keywords:</b> ${(a.matched_keywords || []).join(', ')}</div>
          ${a.video_url ? `<video controls src="${a.video_url}"></video>` : '<p class="sub">No video clip attached</p>'}
        </div>`,
          )
          .join('')
      : '<p class="sub">Koi flagged alert nahi mila.</p>';

    // Recharges
    const recBody = $('recharges-tbody');
    recBody.innerHTML = data.recharges
      .map(
        (r) => `
      <tr>
        <td>${r.user_email}</td>
        <td>₹${r.amount}</td>
        <td>${r.utr}</td>
        <td>${r.status}</td>
        <td>
          ${
            r.status === 'pending'
              ? `<button class="primary" style="padding:5px 10px;font-size:12px" data-rec="${r.id}" data-act="approve">Approve</button>
                 <button class="ghost danger-ghost" style="padding:5px 10px;font-size:12px" data-rec="${r.id}" data-act="reject">Reject</button>`
              : '-'
          }
        </td>
      </tr>`,
      )
      .join('');

    recBody.querySelectorAll('button[data-rec]').forEach((b) => {
      b.addEventListener('click', async () => {
        await api(`/api/admin/recharges/${b.dataset.rec}/${b.dataset.act}`, { method: 'POST' });
        loadOverview();
      });
    });

    // Users
    const usersBody = $('users-tbody');
    usersBody.innerHTML = data.users
      .map(
        (u) => `
      <tr>
        <td>${u.email} ${u.is_admin ? '(Admin)' : ''}</td>
        <td>₹${u.wallet_balance}</td>
        <td>${u.total_questions_asked}</td>
        <td>${u.is_banned ? 'Banned' : 'Active'}</td>
        <td>
          <button class="ghost" style="padding:5px 10px;font-size:12px" data-add50="${u.id}">+₹50</button>
          <button class="ghost danger-ghost" style="padding:5px 10px;font-size:12px" data-ban="${u.id}">${u.is_banned ? 'Unban' : 'Ban'}</button>
        </td>
      </tr>`,
      )
      .join('');

    usersBody.querySelectorAll('button[data-add50]').forEach((b) => {
      b.addEventListener('click', async () => {
        await api(`/api/admin/users/${b.dataset.add50}/wallet`, {
          method: 'POST',
          body: JSON.stringify({ delta: 50 }),
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
  } catch (err) {
    $('admin-err').classList.remove('hidden');
    $('admin-err-text').textContent = err.message;
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
        upi_id: $('set-upi').value,
      }),
    });
    msg.textContent = 'Settings updated live!';
    msg.classList.remove('hidden');
  } catch (err) {
    alert(err.message);
  }
});

loadOverview();
