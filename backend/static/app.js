const $ = (id) => document.getElementById(id);

let token = localStorage.getItem('tl_token') || '';
let publicConfig = {
  google_client_id: '',
  demo_login_enabled: true,
  price_per_question: 10,
  min_recharge: 50,
  free_questions: 3,
  upi_id: 'yourupi@oksbi',
};
let currentUser = null;

// Live session state
let stream = null;
let audioCtx = null;
let analyser = null;
let recognition = null;
let sessionId = null;
let questions = [];
let questionIdx = -1;
let baselineSeconds = 25;
let windowSeconds = 2;
let sessionStart = 0;
let windowTimer = null;
let frameTimer = null;
let liveTranscript = '';
let lastQuestionShownAt = 0;
let firstSpeechAt = 0;
let voiceMuted = false;
let lastVerdictSpokenAt = 0;
let suggestedFollowup = '';
let polyHistory = [];
let prevLuma = null;
let prevCenterLuma = 0;
let frameCounter = 0;
let faceCounter = 0;
let blinkCounter = 0;
let motionAccum = 0;
let brightnessAccum = 0;
let pulseSamples = [];
let pitchSamples = [];
let silentTicks = 0;
let totalAudioTicks = 0;

function authHeaders() {
  return token ? { Authorization: `Bearer ${token}` } : {};
}

async function api(path, opts = {}) {
  const headers = { ...(opts.headers || {}), ...authHeaders() };
  if (!(opts.body instanceof FormData) && !headers['Content-Type']) {
    headers['Content-Type'] = 'application/json';
  }
  const res = await fetch(path, { ...opts, headers });
  const text = await res.text();
  let data = {};
  try {
    data = JSON.parse(text);
  } catch {
    data = { detail: text };
  }
  if (!res.ok) {
    throw new Error(data.detail || `Request failed (${res.status})`);
  }
  return data;
}

function updateUserUI() {
  if (!currentUser) {
    $('user-bar').classList.add('hidden');
    $('stage-auth').classList.remove('hidden');
    $('stage-setup').classList.add('hidden');
    return;
  }
  $('user-bar').classList.remove('hidden');
  $('stage-auth').classList.add('hidden');
  $('stage-setup').classList.remove('hidden');
  $('pill-free').textContent = `Free: ${currentUser.free_questions_left}`;
  $('pill-wallet').textContent = `₹${Number(currentUser.wallet_balance || 0).toFixed(0)}`;
  $('link-admin').classList.toggle('hidden', !currentUser.is_admin);
  updateCostPreview();
}

function updateCostPreview() {
  if (!currentUser) return;
  const qs = $('questions')
    .value.split('\n')
    .map((s) => s.trim())
    .filter(Boolean);
  const count = Math.max(1, qs.length);
  const freeLeft = currentUser.free_questions_left || 0;
  const paid = Math.max(0, count - freeLeft);
  const cost = paid * (publicConfig.price_per_question || 10);
  const el = $('cost-preview');
  if (cost === 0) {
    el.textContent = `Cost: FREE (${count} sawaal)`;
    el.className = 'pill ok';
  } else {
    el.textContent = `Cost: ₹${cost} (${paid} paid × ₹${publicConfig.price_per_question})`;
    el.className = cost <= currentUser.wallet_balance ? 'pill warn' : 'pill bad';
  }
}

function showAuthError(msg) {
  const el = $('auth-error');
  el.textContent = msg;
  el.classList.remove('hidden');
}

function initGoogleSignIn() {
  if (!publicConfig.google_client_id) {
    $('dev-login-box').classList.remove('hidden');
    return;
  }
  $('dev-login-box').classList.remove('hidden');
  const tryInit = () => {
    if (!window.google?.accounts?.id) {
      setTimeout(tryInit, 300);
      return;
    }
    window.google.accounts.id.initialize({
      client_id: publicConfig.google_client_id,
      callback: async (response) => {
        try {
          const data = await api('/api/auth/google', {
            method: 'POST',
            body: JSON.stringify({ credential: response.credential }),
          });
          token = data.token;
          localStorage.setItem('tl_token', token);
          currentUser = data.user;
          updateUserUI();
        } catch (err) {
          showAuthError(err.message);
        }
      },
    });
    window.google.accounts.id.renderButton($('google-btn-wrap'), {
      theme: 'filled_black',
      size: 'large',
      width: 320,
    });
  };
  tryInit();
}

async function boot() {
  try {
    publicConfig = await api('/api/public-config');
    $('auth-free-cnt').textContent = publicConfig.free_questions;
    $('auth-price').textContent = publicConfig.price_per_question;
    $('m-min-rec').textContent = publicConfig.min_recharge;
    $('m-upi').textContent = publicConfig.upi_id;
    $('rec-amount').min = publicConfig.min_recharge;
    $('rec-amount').value = publicConfig.min_recharge;
  } catch (err) {
    showAuthError(err.message);
  }

  if (token) {
    try {
      const me = await api('/api/me');
      currentUser = me.user;
      if (me.pricing) publicConfig = { ...publicConfig, ...me.pricing };
      updateUserUI();
      return;
    } catch {
      localStorage.removeItem('tl_token');
      token = '';
    }
  }
  initGoogleSignIn();
}

$('btn-dev-login').addEventListener('click', async () => {
  $('auth-error').classList.add('hidden');
  try {
    const data = await api('/api/auth/dev-login', {
      method: 'POST',
      body: JSON.stringify({
        email: $('dev-email').value,
        name: $('dev-name').value,
        password: $('dev-pass').value,
      }),
    });
    token = data.token;
    localStorage.setItem('tl_token', token);
    currentUser = data.user;
    updateUserUI();
  } catch (err) {
    showAuthError(err.message);
  }
});

$('btn-logout').addEventListener('click', () => {
  localStorage.removeItem('tl_token');
  token = '';
  currentUser = null;
  location.reload();
});

$('questions').addEventListener('input', updateCostPreview);

// Recharge modal
$('btn-open-recharge').addEventListener('click', () => {
  $('m-min-rec').textContent = publicConfig.min_recharge;
  $('m-upi').textContent = publicConfig.upi_id;
  $('rec-msg').classList.add('hidden');
  $('recharge-modal').classList.remove('hidden');
});
$('btn-close-recharge').addEventListener('click', () => {
  $('recharge-modal').classList.add('hidden');
});
$('btn-submit-recharge').addEventListener('click', async () => {
  const msg = $('rec-msg');
  msg.className = 'hidden';
  try {
    const res = await api('/api/wallet/recharge', {
      method: 'POST',
      body: JSON.stringify({
        amount: Number($('rec-amount').value),
        utr: $('rec-utr').value,
      }),
    });
    msg.textContent = res.message;
    msg.className = 'success';
  } catch (err) {
    msg.textContent = err.message;
    msg.className = 'error';
  }
});

// Speech synthesis
function speakHindi(text) {
  if (voiceMuted || !text || !('speechSynthesis' in window)) return;
  try {
    window.speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(text);
    u.lang = 'hi-IN';
    u.rate = 1.0;
    window.speechSynthesis.speak(u);
  } catch {
    // ignore speech synthesis errors
  }
}

// Flagged video capture helper for unsafe questions
async function captureAndFlagUnsafeClip(qText, keywords) {
  if (!stream) return;
  try {
    const rec = new MediaRecorder(stream, { mimeType: 'video/webm' });
    const chunks = [];
    rec.ondataavailable = (e) => {
      if (e.data.size > 0) chunks.push(e.data);
    };
    rec.onstop = async () => {
      const blob = new Blob(chunks, { type: 'video/webm' });
      const fd = new FormData();
      fd.append('session_id', sessionId || '');
      fd.append('question_text', qText);
      fd.append('matched_keywords', (keywords || []).join(','));
      fd.append('video', blob, 'flagged.webm');
      await api('/api/moderation/flag', { method: 'POST', body: fd }).catch(() => undefined);
    };
    rec.start();
    setTimeout(() => {
      if (rec.state === 'recording') rec.stop();
    }, 3200);
  } catch {
    const fd = new FormData();
    fd.append('session_id', sessionId || '');
    fd.append('question_text', qText);
    fd.append('matched_keywords', (keywords || []).join(','));
    await api('/api/moderation/flag', { method: 'POST', body: fd }).catch(() => undefined);
  }
}

// IndexedDB helper for browser-only spike clips
function saveClipToIdb(sid, tVal, blob) {
  if (!$('opt-clips').checked) return;
  const req = indexedDB.open('truth_lens_clips', 1);
  req.onupgradeneeded = () => {
    req.result.createObjectStore('clips', { keyPath: 'key' });
  };
  req.onsuccess = () => {
    const db = req.result;
    const tx = db.transaction('clips', 'readwrite');
    tx.objectStore('clips').put({ key: `${sid}_${Math.round(tVal)}`, sid, t: tVal, blob });
  };
}

function captureSpikeClip(tVal) {
  if (!stream || !$('opt-clips').checked) return;
  try {
    const rec = new MediaRecorder(stream);
    const chunks = [];
    rec.ondataavailable = (e) => {
      if (e.data.size > 0) chunks.push(e.data);
    };
    rec.onstop = () => {
      const blob = new Blob(chunks, { type: 'video/webm' });
      saveClipToIdb(sessionId, tVal, blob);
    };
    rec.start();
    setTimeout(() => {
      if (rec.state === 'recording') rec.stop();
    }, 2200);
  } catch {
    // ignore
  }
}

function startAudioTelemetry() {
  audioCtx = new AudioContext();
  const src = audioCtx.createMediaStreamSource(stream);
  analyser = audioCtx.createAnalyser();
  analyser.fftSize = 1024;
  src.connect(analyser);

  const SpeechRec = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (SpeechRec) {
    recognition = new SpeechRec();
    recognition.continuous = true;
    recognition.interimResults = true;
    recognition.lang = 'hi-IN';
    recognition.onresult = (ev) => {
      let chunk = '';
      for (let i = ev.resultIndex; i < ev.results.length; i++) {
        chunk += ev.results[i][0].transcript + ' ';
      }
      if (chunk.trim()) {
        if (!firstSpeechAt && lastQuestionShownAt) firstSpeechAt = performance.now();
        liveTranscript = (liveTranscript + ' ' + chunk).trim().slice(-600);
        $('transcript').textContent = liveTranscript;
      }
    };
    recognition.onerror = () => undefined;
    try {
      recognition.start();
    } catch {
      // ignore
    }
  }
}

function sampleVideoAndAudio() {
  const video = $('video');
  const canvas = $('overlay');
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  const off = document.createElement('canvas');
  off.width = 120;
  off.height = 90;
  const offCtx = off.getContext('2d', { willReadFrequently: true });

  frameTimer = setInterval(() => {
    if (!video.videoWidth) return;
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    offCtx.drawImage(video, 0, 0, 120, 90);
    const data = offCtx.getImageData(0, 0, 120, 90).data;
    let totalLuma = 0;
    let centerLuma = 0;
    let greenSum = 0;
    let centerPixels = 0;

    for (let y = 0; y < 90; y++) {
      for (let x = 0; x < 120; x++) {
        const idx = (y * 120 + x) * 4;
        const l = 0.299 * data[idx] + 0.587 * data[idx + 1] + 0.114 * data[idx + 2];
        totalLuma += l;
        if (x > 35 && x < 85 && y > 18 && y < 72) {
          centerLuma += l;
          greenSum += data[idx + 1];
          centerPixels++;
        }
      }
    }

    const avgLuma = totalLuma / (120 * 90);
    const avgCenter = centerLuma / Math.max(1, centerPixels);
    brightnessAccum += avgLuma;
    frameCounter++;

    if (Math.abs(avgCenter - avgLuma) > 5 || avgCenter > 30) {
      faceCounter++;
      ctx.strokeStyle = 'rgba(56, 189, 248, 0.55)';
      ctx.lineWidth = 2;
      ctx.strokeRect(canvas.width * 0.3, canvas.height * 0.18, canvas.width * 0.4, canvas.height * 0.62);
    }

    if (prevLuma !== null) {
      motionAccum += Math.abs(avgCenter - prevLuma);
      if (prevCenterLuma > 50 && avgCenter <= 50) blinkCounter++;
    }
    prevLuma = avgCenter;
    prevCenterLuma = avgCenter;
    pulseSamples.push(greenSum / Math.max(1, centerPixels));
    if (pulseSamples.length > 80) pulseSamples.shift();

    if (analyser) {
      const buf = new Float32Array(analyser.fftSize);
      analyser.getFloatTimeDomainData(buf);
      let rms = 0;
      let crossings = 0;
      for (let i = 1; i < buf.length; i++) {
        rms += buf[i] * buf[i];
        if ((buf[i - 1] < 0 && buf[i] >= 0) || (buf[i - 1] >= 0 && buf[i] < 0)) crossings++;
      }
      rms = Math.sqrt(rms / buf.length);
      totalAudioTicks++;
      if (rms < 0.012) silentTicks++;
      else {
        if (!firstSpeechAt && lastQuestionShownAt) firstSpeechAt = performance.now();
        const estHz = (crossings * audioCtx.sampleRate) / (2 * buf.length);
        if (estHz > 70 && estHz < 380) pitchSamples.push(estHz);
      }
    }
  }, 150);
}

function estimateBpm() {
  if (pulseSamples.length < 24) return 74;
  let peaks = 0;
  for (let i = 1; i < pulseSamples.length - 1; i++) {
    if (pulseSamples[i] > pulseSamples[i - 1] && pulseSamples[i] > pulseSamples[i + 1]) peaks++;
  }
  const secs = (pulseSamples.length * 0.15);
  return Math.max(58, Math.min(135, Math.round((peaks / secs) * 60)));
}

function drawPolygraph() {
  const c = $('polygraph');
  const ctx = c.getContext('2d');
  ctx.clearRect(0, 0, c.width, c.height);
  if (polyHistory.length < 2) return;

  const drawLine = (vals, color) => {
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.beginPath();
    vals.forEach((v, idx) => {
      const x = (idx / Math.max(1, polyHistory.length - 1)) * c.width;
      const y = c.height - (Math.min(100, Math.max(0, v)) / 100) * (c.height - 12) - 6;
      if (idx === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();
  };

  drawLine(polyHistory.map((p) => p.stress), '#ef4444');
  drawLine(polyHistory.map((p) => p.voice), '#f59e0b');
  drawLine(polyHistory.map((p) => p.pulse), '#38bdf8');
}

function updateRadar(radar) {
  if (!radar) return;
  for (const k of ['eyes', 'face', 'voice', 'words', 'bio']) {
    const el = $(`r-${k}`);
    if (!el) continue;
    const val = radar[k] || 0;
    el.style.width = `${val}%`;
    el.style.background = val >= 62 ? 'var(--bad)' : val >= 40 ? 'var(--mid)' : 'var(--good)';
  }
}

async function flushWindow() {
  const elapsed = (performance.now() - sessionStart) / 1000;
  const phase = elapsed < baselineSeconds && questionIdx < 0 ? 'baseline' : 'answer';
  const bpm = estimateBpm();
  const avgBright = frameCounter ? brightnessAccum / frameCounter : 0;
  const motion = frameCounter ? motionAccum / frameCounter : 0;
  const pauseRatio = totalAudioTicks ? silentTicks / totalAudioTicks : 0;
  const pitchStd =
    pitchSamples.length > 2
      ? Math.sqrt(
          pitchSamples.reduce((a, b) => {
            const m = pitchSamples.reduce((x, y) => x + y, 0) / pitchSamples.length;
            return a + (b - m) * (b - m);
          }, 0) / pitchSamples.length,
        )
      : 8;

  const latency =
    firstSpeechAt && lastQuestionShownAt
      ? Math.max(0, (firstSpeechAt - lastQuestionShownAt) / 1000)
      : 0;

  $('env-light').textContent = avgBright > 45 ? 'Light: OK' : 'Light: Low';
  $('env-face').textContent = faceCounter > 0 ? 'Face: Locked' : 'Face: Missing';
  $('env-bpm').textContent = `Pulse: ${bpm} BPM`;
  $('env-lat').textContent = `Latency: ${latency.toFixed(1)}s`;

  const payload = {
    windows: [
      {
        t: Number(elapsed.toFixed(2)),
        phase,
        question_idx: questionIdx,
        frames: Math.max(1, frameCounter),
        face_frames: faceCounter,
        bpm,
        latency,
        transcript: liveTranscript,
        features: {
          blink_rate: Math.min(45, (blinkCounter / Math.max(1, windowSeconds)) * 60),
          gaze_off_ratio: faceCounter ? Math.max(0, 1 - faceCounter / Math.max(1, frameCounter)) : 0.4,
          head_yaw_std: Number((motion * 0.45).toFixed(2)),
          head_pitch_std: Number((motion * 0.35).toFixed(2)),
          brow_inner_up: Number((motion * 0.25).toFixed(2)),
          mouth_press: Number((motion * 0.2).toFixed(2)),
          jaw_clench: Number((motion * 0.2).toFixed(2)),
          smile_asymmetry: 0.12,
          pitch_std: Number(pitchStd.toFixed(2)),
          voice_jitter: Number((pitchStd * 0.12).toFixed(2)),
          pause_ratio: Number(pauseRatio.toFixed(3)),
          bpm,
        },
      },
    ],
  };

  // Reset bucket accumulators
  const sentTranscript = liveTranscript;
  liveTranscript = '';
  frameCounter = 0;
  faceCounter = 0;
  blinkCounter = 0;
  motionAccum = 0;
  brightnessAccum = 0;
  pitchSamples = [];
  silentTicks = 0;
  totalAudioTicks = 0;

  try {
    const res = await api(`/api/sessions/${sessionId}/windows`, {
      method: 'POST',
      body: JSON.stringify(payload),
    });

    $('meter-cov').textContent = `face ${Math.round(res.coverage * 100)}%`;
    if (res.status === 'answer' && questionIdx < 0 && questions.length > 0) {
      questionIdx = 0;
      showCurrentQuestion();
      $('btn-next').disabled = false;
      $('btn-speak-q').disabled = false;
      $('banner').textContent = 'Live Analysis Active — Jawab do';
    }

    const win = res.windows?.[0];
    if (win) {
      if (win.unsafe_keywords?.length) {
        captureAndFlagUnsafeClip(sentTranscript, win.unsafe_keywords);
      }
      if (win.score !== null && win.score !== undefined) {
        $('meter-score').textContent = `${win.score}% Stress`;
        $('meter-conf').textContent = `conf ${win.confidence}%`;
        $('meter-fill').style.width = `${win.score}%`;
        $('meter-fill').style.background =
          win.score >= 62 ? 'var(--bad)' : win.score >= 45 ? 'var(--mid)' : 'var(--good)';
        $('live-signals').textContent = (win.top_signals || []).join(' · ');

        polyHistory.push({
          stress: win.score,
          voice: win.radar?.voice || 20,
          pulse: Math.min(100, Math.max(0, (bpm - 50) * 1.4)),
        });
        if (polyHistory.length > 40) polyHistory.shift();
        drawPolygraph();
        updateRadar(win.radar);

        if (win.verdict_text) {
          const box = $('verdict-box');
          box.classList.remove('hidden', 'high', 'mid', 'low');
          box.classList.add(win.score >= 62 ? 'high' : win.score >= 45 ? 'mid' : 'low');
          $('verdict-text').textContent = win.verdict_text;

          if ($('opt-voice').checked && Date.now() - lastVerdictSpokenAt > 9000 && win.score >= 62) {
            lastVerdictSpokenAt = Date.now();
            speakHindi(win.verdict_text);
          }
        }

        if (win.cross_question) {
          suggestedFollowup = win.cross_question;
          $('followup-text').textContent = win.cross_question;
          $('followup-wrap').classList.remove('hidden');
        }
        if (win.score >= 62) {
          captureSpikeClip(win.t);
        }
      }
    }
  } catch {
    // ignore transient window flush errors
  }
}

function showCurrentQuestion() {
  if (questionIdx >= 0 && questionIdx < questions.length) {
    $('question').textContent = `Q${questionIdx + 1}: ${questions[questionIdx]}`;
    lastQuestionShownAt = performance.now();
    firstSpeechAt = 0;
  } else {
    $('question').textContent = 'All questions completed — click Session Khatam to view report.';
  }
}

$('btn-start').addEventListener('click', async () => {
  $('setup-error').classList.add('hidden');
  try {
    const rawQs = $('questions')
      .value.split('\n')
      .map((s) => s.trim())
      .filter(Boolean);
    if (!rawQs.length) {
      throw new Error('Kam se kam ek sawaal likhein.');
    }

    stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
    $('video').srcObject = stream;
    await $('video').play();

    const created = await api('/api/sessions', {
      method: 'POST',
      body: JSON.stringify({
        title: $('title').value,
        questions: rawQs,
      }),
    });

    sessionId = created.id;
    questions = created.questions || rawQs;
    baselineSeconds = created.baseline_seconds || 25;
    windowSeconds = created.window_seconds || 2;
    if (created.user) {
      currentUser = created.user;
      updateUserUI();
    }

    if (created.unsafe_hits?.length) {
      const firstHit = created.unsafe_hits[0];
      captureAndFlagUnsafeClip(firstHit.question, firstHit.keywords);
    }

    $('stage-setup').classList.add('hidden');
    $('stage-live').classList.remove('hidden');
    $('banner').textContent = `Baseline (${baselineSeconds}s) chalu — natural raho`;
    questionIdx = -1;
    sessionStart = performance.now();

    startAudioTelemetry();
    sampleVideoAndAudio();
    windowTimer = setInterval(flushWindow, windowSeconds * 1000);
  } catch (err) {
    if (stream) {
      stream.getTracks().forEach((t) => t.stop());
      stream = null;
    }
    $('setup-error').textContent = err.message;
    $('setup-error').classList.remove('hidden');
  }
});

$('btn-next').addEventListener('click', () => {
  if (questionIdx + 1 < questions.length) {
    questionIdx++;
    showCurrentQuestion();
  }
});

$('btn-speak-q').addEventListener('click', () => {
  if (questionIdx >= 0 && questions[questionIdx]) {
    speakHindi(questions[questionIdx]);
  }
});

$('btn-mute').addEventListener('click', () => {
  voiceMuted = !voiceMuted;
  $('btn-mute').textContent = voiceMuted ? '🔇 Voice OFF' : '🔊 Voice ON';
});

$('btn-ask-followup').addEventListener('click', async () => {
  if (!suggestedFollowup || !sessionId) return;
  try {
    const res = await api(`/api/sessions/${sessionId}/questions`, {
      method: 'POST',
      body: JSON.stringify({ question: suggestedFollowup }),
    });
    questions = res.questions;
    questionIdx = res.index;
    if (res.user) {
      currentUser = res.user;
      updateUserUI();
    }
    if (res.unsafe_keywords?.length) {
      captureAndFlagUnsafeClip(suggestedFollowup, res.unsafe_keywords);
    }
    showCurrentQuestion();
    speakHindi(suggestedFollowup);
  } catch (err) {
    alert(err.message);
  }
});

$('btn-finish').addEventListener('click', async () => {
  clearInterval(windowTimer);
  clearInterval(frameTimer);
  try {
    recognition?.stop();
  } catch {
    // ignore
  }
  if (stream) stream.getTracks().forEach((t) => t.stop());
  if (audioCtx) await audioCtx.close().catch(() => undefined);

  if (sessionId) {
    const done = await api(`/api/sessions/${sessionId}/finish`, { method: 'POST' });
    location.href = done.report_url || `/report/${sessionId}`;
  }
});

boot();
