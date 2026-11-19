const token = localStorage.getItem('tl_token') || '';
const listEl = document.getElementById('list');

async function loadHistory() {
  if (!token) {
    listEl.innerHTML = '<p class="error">History dekhne ke liye pehle login karein.</p>';
    return;
  }
  try {
    const res = await fetch('/api/sessions', {
      headers: { Authorization: `Bearer ${token}` },
    });
    const rows = await res.json();
    if (!res.ok) throw new Error(rows.detail || 'Failed to load sessions');
    if (!rows.length) {
      listEl.innerHTML = '<p class="sub">Abhi koi session record nahi hua hai.</p>';
      return;
    }
    listEl.innerHTML = rows
      .map(
        (s) => `
      <div class="h-item">
        <div>
          <p class="h-title">${s.title}</p>
          <p class="sub">${new Date(s.created_at).toLocaleString()} · Score: ${s.overall_score ?? '--'}% · Spikes: ${s.spikes_count} · ${s.overall_verdict}</p>
        </div>
        <div class="row">
          <a href="/report/${s.id}" class="primary btn-link" style="padding:7px 12px;font-size:13px">View Report</a>
          <button class="ghost danger-ghost" style="padding:7px 12px;font-size:13px" data-del="${s.id}">Delete</button>
        </div>
      </div>`,
      )
      .join('');

    listEl.querySelectorAll('button[data-del]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        await fetch(`/api/sessions/${btn.dataset.del}`, {
          method: 'DELETE',
          headers: { Authorization: `Bearer ${token}` },
        });
        loadHistory();
      });
    });
  } catch (err) {
    listEl.innerHTML = `<p class="error">${err.message}</p>`;
  }
}

loadHistory();
