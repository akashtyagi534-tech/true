const $ = (id) => document.getElementById(id);
const sessionId = location.pathname.split('/').filter(Boolean).pop();
let reportData = null;

function openClipModal(tVal) {
  const req = indexedDB.open('truth_lens_clips', 1);
  req.onsuccess = () => {
    const db = req.result;
    if (!db.objectStoreNames.contains('clips')) return;
    const tx = db.transaction('clips', 'readonly');
    const getReq = tx.objectStore('clips').get(`${sessionId}_${Math.round(tVal)}`);
    getReq.onsuccess = () => {
      if (!getReq.result?.blob) return alert('Local browser clip not found for this spike.');
      $('clip-video').src = URL.createObjectURL(getReq.result.blob);
      $('clip-modal').classList.remove('hidden');
    };
  };
}

$('btn-close-clip').addEventListener('click', () => {
  $('clip-modal').classList.add('hidden');
  $('clip-video').pause();
});

async function loadReport() {
  const res = await fetch(`/api/sessions/${sessionId}`);
  const data = await res.json();
  reportData = data;

  $('title').textContent = data.title || 'Session Report';
  $('meta').textContent = `${new Date(data.created_at).toLocaleString()} · Status: ${data.status}`;
  $('overall').textContent = data.overall_score !== null ? `${data.overall_score}%` : '--';
  $('spikes-cnt').textContent = data.spikes.length;
  $('bpm-stat').textContent = `${data.avg_bpm ?? '--'} / ${data.baseline_bpm ?? '--'} BPM`;
  $('cov-stat').textContent = `${Math.round((data.face_coverage || 0) * 100)}%`;

  const vb = $('verdict-badge');
  vb.textContent = data.overall_verdict;
  vb.style.background =
    (data.overall_score || 0) >= 62 ? 'rgba(239,68,68,0.2)' : (data.overall_score || 0) >= 45 ? 'rgba(245,158,11,0.2)' : 'rgba(34,197,94,0.2)';

  $('conf').textContent = `CONFIDENCE: ${data.confidence_label}`;

  $('bar').innerHTML = data.windows
    .map((w) => {
      const s = w.score ?? 10;
      const col = s >= 62 ? 'var(--bad)' : s >= 45 ? 'var(--mid)' : 'var(--good)';
      return `<div style="height:${Math.max(5, s)}%;background:${col}" title="${w.t}s: ${s}%"></div>`;
    })
    .join('');

  if (data.contradictions?.length) {
    $('contra-card').classList.remove('hidden');
    $('contra-list').innerHTML = data.contradictions
      .map((c) => `<div class="contra-item"><b>${c.type}</b> (${c.t_first}s → ${c.t_second}s): ${c.message}</div>`)
      .join('');
  }

  const byQ = {};
  for (const w of data.windows) {
    const idx = w.question_idx >= 0 ? w.question_idx : 0;
    (byQ[idx] ||= []).push(w);
  }

  $('detail').innerHTML = Object.entries(byQ)
    .map(([idx, wins]) => {
      const qTitle = data.questions[Number(idx)] || `Question ${Number(idx) + 1}`;
      const rows = wins
        .map(
          (w) => `
        <div class="wrow">
          <div><b>${w.t}s</b></div>
          <div>
            <b>${w.score ?? '--'}%</b>
            ${w.score >= 62 ? `<button class="clip-btn" data-clip="${w.t}">Clip</button>` : ''}
            <div class="reason-line">${(w.top_signals || []).join(', ')}</div>
          </div>
          <div>${w.transcript || '<span class="sub">(no transcript)</span>'}</div>
        </div>`,
        )
        .join('');
      return `<div class="qblock"><h3>Q${Number(idx) + 1}: ${qTitle}</h3>${rows}</div>`;
    })
    .join('');

  $('detail').querySelectorAll('button[data-clip]').forEach((btn) => {
    btn.addEventListener('click', () => openClipModal(Number(btn.dataset.clip)));
  });
}

$('btn-read').addEventListener('click', () => {
  if (!reportData || !('speechSynthesis' in window)) return;
  const u = new SpeechSynthesisUtterance(
    `Session ${reportData.title}. Overall stress index ${reportData.overall_score ?? 0} percent. Verdict: ${reportData.overall_verdict}.`,
  );
  u.lang = 'hi-IN';
  window.speechSynthesis.speak(u);
});

$('btn-json').addEventListener('click', () => {
  if (!reportData) return;
  const blob = new Blob([JSON.stringify(reportData, null, 2)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `truth-lens-${sessionId}.json`;
  a.click();
});

$('btn-pdf').addEventListener('click', () => window.print());

loadReport();
