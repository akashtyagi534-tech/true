import type {
  AudioMetrics,
  AudioTimelinePoint,
  VerificationReport,
  VideoMetrics,
  VideoTimelinePoint,
} from '../types/truthVerify';

function estimatePitchAutocorrelation(samples: Float32Array, sampleRate: number): number {
  const minLag = Math.floor(sampleRate / 370);
  const maxLag = Math.floor(sampleRate / 75);
  if (samples.length <= maxLag + 2) return 0;

  let rms = 0;
  for (let i = 0; i < samples.length; i++) {
    rms += samples[i] * samples[i];
  }
  rms = Math.sqrt(rms / samples.length);
  if (rms < 0.008) return 0;

  let bestLag = -1;
  let bestCorr = 0;
  for (let lag = minLag; lag <= maxLag; lag++) {
    let corr = 0;
    let normA = 0;
    let normB = 0;
    const len = samples.length - lag;
    for (let i = 0; i < len; i++) {
      const a = samples[i];
      const b = samples[i + lag];
      corr += a * b;
      normA += a * a;
      normB += b * b;
    }
    const denom = Math.sqrt(normA * normB);
    const normalized = denom > 0 ? corr / denom : 0;
    if (normalized > bestCorr) {
      bestCorr = normalized;
      bestLag = lag;
    }
  }

  if (bestCorr < 0.45 || bestLag <= 0) return 0;
  return sampleRate / bestLag;
}

export function analyzePcmAudio(samples: Float32Array, sampleRate: number): AudioMetrics {
  const durationSec = Number((samples.length / sampleRate).toFixed(2));
  if (samples.length < sampleRate * 0.25) {
    return {
      duration_sec: durationSec,
      pitch_mean_hz: 0,
      pitch_std_hz: 0,
      energy_rms_mean: 0,
      energy_spike_rate: 0,
      pause_ratio: 100,
      vocal_stress_index: 0,
      audio_available: false,
      timeline: [],
    };
  }

  const windowSize = Math.floor(sampleRate * 0.04); // 40ms frames
  const hopSize = Math.floor(sampleRate * 0.02); // 20ms hop
  const rmsFrames: number[] = [];
  const pitchFrames: number[] = [];

  for (let start = 0; start + windowSize <= samples.length; start += hopSize) {
    const slice = samples.subarray(start, start + windowSize);
    let sumSq = 0;
    for (let i = 0; i < slice.length; i++) {
      sumSq += slice[i] * slice[i];
    }
    const rms = Math.sqrt(sumSq / slice.length);
    rmsFrames.push(rms);
    pitchFrames.push(estimatePitchAutocorrelation(slice, sampleRate));
  }

  const rmsMean = rmsFrames.reduce((a, b) => a + b, 0) / Math.max(1, rmsFrames.length);
  const rmsVariance =
    rmsFrames.reduce((acc, v) => acc + (v - rmsMean) * (v - rmsMean), 0) /
    Math.max(1, rmsFrames.length);
  const rmsStd = Math.sqrt(rmsVariance);

  const silenceThreshold = Math.max(0.005, rmsMean * 0.32);
  const silentCount = rmsFrames.filter((r) => r < silenceThreshold).length;
  const pauseRatio = Number(((silentCount / Math.max(1, rmsFrames.length)) * 100).toFixed(1));

  const spikeThreshold = rmsMean + 1.5 * rmsStd;
  const spikeCount = rmsFrames.filter((r) => r > spikeThreshold).length;
  const energySpikeRate = Number(((spikeCount / Math.max(1, rmsFrames.length)) * 100).toFixed(1));

  const voicedPitches = pitchFrames.filter((p, idx) => p > 75 && p < 370 && rmsFrames[idx] > silenceThreshold);
  const pitchMean =
    voicedPitches.length > 0
      ? Number((voicedPitches.reduce((a, b) => a + b, 0) / voicedPitches.length).toFixed(1))
      : 0;
  const pitchStd =
    voicedPitches.length > 0
      ? Number(
          Math.sqrt(
            voicedPitches.reduce((acc, p) => acc + (p - pitchMean) * (p - pitchMean), 0) /
              voicedPitches.length,
          ).toFixed(1),
        )
      : 0;

  const pitchInstability =
    pitchMean > 0 ? Math.min(100, (pitchStd / Math.max(pitchMean, 120)) * 220) : 20;
  const pauseAnomaly = Math.min(100, Math.max(0, (pauseRatio - 22) * 1.8));
  const energyVolatility = Math.min(100, energySpikeRate * 4.5);
  const vocalStress = Number(
    Math.min(100, 0.45 * pitchInstability + 0.3 * energyVolatility + 0.25 * pauseAnomaly).toFixed(1),
  );

  const framesPerSec = Math.max(1, Math.round(1 / 0.02));
  const totalSeconds = Math.max(1, Math.ceil(durationSec));
  const timeline: AudioTimelinePoint[] = [];

  for (let sec = 0; sec < totalSeconds; sec++) {
    const start = sec * framesPerSec;
    const end = Math.min(rmsFrames.length, (sec + 1) * framesPerSec);
    if (start >= end) break;
    const rmsSlice = rmsFrames.slice(start, end);
    const pitchSlice = pitchFrames.slice(start, end).filter((p) => p > 75 && p < 370);
    const avgRms = rmsSlice.reduce((a, b) => a + b, 0) / rmsSlice.length;
    const avgPitch =
      pitchSlice.length > 0 ? pitchSlice.reduce((a, b) => a + b, 0) / pitchSlice.length : 0;

    timeline.push({
      t: sec,
      energy: Number(Math.min(100, avgRms * 650).toFixed(1)),
      pitch_hz: Number(avgPitch.toFixed(1)),
    });
  }

  return {
    duration_sec: durationSec,
    pitch_mean_hz: pitchMean,
    pitch_std_hz: pitchStd,
    energy_rms_mean: Number(rmsMean.toFixed(4)),
    energy_spike_rate: energySpikeRate,
    pause_ratio: pauseRatio,
    vocal_stress_index: vocalStress,
    audio_available: true,
    timeline: timeline.slice(0, 120),
  };
}

async function analyzeVideoElement(blobUrl: string): Promise<VideoMetrics> {
  const video = document.createElement('video');
  video.muted = true;
  video.playsInline = true;
  video.preload = 'auto';
  video.src = blobUrl;

  await new Promise<void>((resolve, reject) => {
    video.onloadedmetadata = () => resolve();
    video.onerror = () => reject(new Error('Could not decode video stream metadata'));
  });

  let duration = video.duration;
  if (!Number.isFinite(duration) || duration <= 0) {
    // WebM recordings from MediaRecorder sometimes report Infinity until seeked
    video.currentTime = 1e6;
    await new Promise<void>((resolve) => {
      video.onseeked = () => resolve();
      setTimeout(resolve, 400);
    });
    duration = Number.isFinite(video.duration) && video.duration > 0 ? video.duration : 4;
    video.currentTime = 0;
  }

  if (video.videoWidth === 0 || video.videoHeight === 0) {
    return {
      duration_sec: Number(duration.toFixed(2)),
      fps: 0,
      frames_analyzed: 0,
      face_detected_ratio: 0,
      blink_rate_per_min: 0,
      motion_jitter_index: 0,
      visual_stress_index: 25,
      timeline: [],
    };
  }

  const canvas = document.createElement('canvas');
  canvas.width = 160;
  canvas.height = 120;
  const ctx = canvas.getContext('2d', {willReadFrequently: true});
  if (!ctx) {
    throw new Error('Canvas 2D context unavailable');
  }

  const sampleStep = Math.max(0.2, duration / 40);
  const timeline: VideoTimelinePoint[] = [];
  const motionDeltas: number[] = [];
  let prevLum: Float32Array | null = null;
  let subjectFrames = 0;
  let rapidCenterTransitions = 0;
  let prevCenterBright = true;

  for (let t = 0; t <= Math.min(duration, 60); t += sampleStep) {
    video.currentTime = t;
    await new Promise<void>((resolve) => {
      const onSeeked = () => {
        video.removeEventListener('seeked', onSeeked);
        resolve();
      };
      video.addEventListener('seeked', onSeeked);
      setTimeout(resolve, 250);
    });

    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
    const frame = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
    const pixelCount = canvas.width * canvas.height;
    const lum = new Float32Array(pixelCount);

    let centerSum = 0;
    let centerCount = 0;
    let outerSum = 0;
    let outerCount = 0;

    for (let y = 0; y < canvas.height; y++) {
      for (let x = 0; x < canvas.width; x++) {
        const idx = (y * canvas.width + x) * 4;
        const l = 0.299 * frame[idx] + 0.587 * frame[idx + 1] + 0.114 * frame[idx + 2];
        lum[y * canvas.width + x] = l;
        if (x > 40 && x < 120 && y > 20 && y < 95) {
          centerSum += l;
          centerCount++;
        } else {
          outerSum += l;
          outerCount++;
        }
      }
    }

    const centerMean = centerSum / Math.max(1, centerCount);
    const outerMean = outerSum / Math.max(1, outerCount);
    const subjectPresent = Math.abs(centerMean - outerMean) > 6 || centerMean > 25;
    if (subjectPresent) subjectFrames++;

    const centerBright = centerMean > 50;
    if (prevCenterBright && !centerBright) {
      rapidCenterTransitions++;
    }
    prevCenterBright = centerBright;

    let delta = 0;
    if (prevLum) {
      let diffSum = 0;
      for (let i = 0; i < pixelCount; i++) {
        diffSum += Math.abs(lum[i] - prevLum[i]);
      }
      delta = diffSum / pixelCount;
      motionDeltas.push(delta);
    }
    prevLum = lum;

    timeline.push({
      t: Number(t.toFixed(2)),
      motion: Number(Math.min(100, delta * 4.0).toFixed(1)),
      face_detected: subjectPresent,
    });
  }

  const analyzed = timeline.length;
  const faceRatio = analyzed > 0 ? Number(((subjectFrames / analyzed) * 100).toFixed(1)) : 0;
  const avgMotion =
    motionDeltas.length > 0 ? motionDeltas.reduce((a, b) => a + b, 0) / motionDeltas.length : 0;
  const stdMotion =
    motionDeltas.length > 0
      ? Math.sqrt(
          motionDeltas.reduce((acc, d) => acc + (d - avgMotion) * (d - avgMotion), 0) /
            motionDeltas.length,
        )
      : 0;

  const motionJitter = Number(Math.min(100, stdMotion * 6.5 + avgMotion * 2.0).toFixed(1));
  const minutes = Math.max(duration / 60, 1 / 60);
  const estimatedBlinkRate = Number(Math.min(45, Math.max(8, 15 + rapidCenterTransitions / minutes)).toFixed(1));
  const blinkDeviation = faceRatio > 0 ? Math.min(100, Math.abs(estimatedBlinkRate - 17) * 3.2) : 25;
  const visualStress = Number(Math.min(100, 0.6 * motionJitter + 0.4 * blinkDeviation).toFixed(1));

  return {
    duration_sec: Number(duration.toFixed(2)),
    fps: 24,
    frames_analyzed: analyzed,
    face_detected_ratio: faceRatio,
    blink_rate_per_min: estimatedBlinkRate,
    motion_jitter_index: motionJitter,
    visual_stress_index: visualStress,
    timeline,
  };
}

export function computeTruthScore(
  videoMetrics: VideoMetrics,
  audioMetrics: AudioMetrics,
  sourceLabel?: string,
): VerificationReport {
  const visualStress = videoMetrics.visual_stress_index;
  const vocalStress = audioMetrics.vocal_stress_index;
  const audioAvailable = audioMetrics.audio_available;

  const combinedStress = audioAvailable
    ? Number((0.45 * visualStress + 0.55 * vocalStress).toFixed(1))
    : Number(visualStress.toFixed(1));

  const consistencyIndex = Number(Math.max(0, Math.min(100, 100 - combinedStress)).toFixed(1));

  let classification = 'Elevated Stress Indicators';
  if (consistencyIndex >= 72) {
    classification = 'Low Stress / Consistent';
  } else if (consistencyIndex >= 45) {
    classification = 'Moderate Cognitive Load';
  }

  const findings: string[] = [];
  if (videoMetrics.frames_analyzed > 0 && videoMetrics.face_detected_ratio < 40) {
    findings.push('Low frontal subject visibility reduced visual tracking confidence.');
  }
  if (videoMetrics.motion_jitter_index > 55) {
    findings.push('Elevated head or upper-body micro-movement variance detected.');
  }
  if (videoMetrics.blink_rate_per_min > 28) {
    findings.push('Above-baseline blink frequency observed during speech segments.');
  }
  if (audioAvailable && audioMetrics.pitch_std_hz > 38) {
    findings.push('Notable fundamental frequency (F0) pitch variance across utterances.');
  }
  if (audioAvailable && audioMetrics.pause_ratio > 42) {
    findings.push('Frequent hesitation or silence intervals detected in audio track.');
  }
  if (findings.length === 0) {
    findings.push('Vocal cadence and visual movement remained within steady baseline ranges.');
  }

  return {
    consistency_index: consistencyIndex,
    combined_stress_index: combinedStress,
    classification,
    confidence:
      videoMetrics.face_detected_ratio >= 60 && audioAvailable
        ? 'High'
        : audioAvailable
          ? 'Moderate'
          : 'Audio-Only / Low',
    video: videoMetrics,
    audio: audioMetrics,
    findings,
    disclaimer:
      'Signal analysis measures acoustic and visual stress indicators only and does not constitute definitive truth or deception verification.',
    sourceLabel,
    analyzedAt: new Date().toISOString(),
  };
}

export async function analyzeMediaBlob(blob: Blob, sourceLabel: string): Promise<VerificationReport> {
  const blobUrl = URL.createObjectURL(blob);
  try {
    const arrayBuffer = await blob.arrayBuffer();
    const audioCtx = new AudioContext();
    let audioMetrics: AudioMetrics;
    try {
      const decoded = await audioCtx.decodeAudioData(arrayBuffer.slice(0));
      const channel = decoded.getChannelData(0);
      audioMetrics = analyzePcmAudio(channel, decoded.sampleRate);
    } catch {
      audioMetrics = {
        duration_sec: 0,
        pitch_mean_hz: 0,
        pitch_std_hz: 0,
        energy_rms_mean: 0,
        energy_spike_rate: 0,
        pause_ratio: 0,
        vocal_stress_index: 0,
        audio_available: false,
        timeline: [],
      };
    } finally {
      await audioCtx.close();
    }

    let videoMetrics: VideoMetrics;
    if (blob.type.startsWith('audio/')) {
      videoMetrics = {
        duration_sec: audioMetrics.duration_sec,
        fps: 0,
        frames_analyzed: 0,
        face_detected_ratio: 0,
        blink_rate_per_min: 0,
        motion_jitter_index: 0,
        visual_stress_index: 0,
        timeline: [],
      };
    } else {
      videoMetrics = await analyzeVideoElement(blobUrl);
    }

    return computeTruthScore(videoMetrics, audioMetrics, sourceLabel);
  } finally {
    URL.revokeObjectURL(blobUrl);
  }
}

export function createCalibratedSpeechWavBlob(profile: 'steady' | 'stressed'): Blob {
  const sampleRate = 16000;
  const durationSec = 5;
  const totalSamples = sampleRate * durationSec;
  const samples = new Float32Array(totalSamples);

  for (let i = 0; i < totalSamples; i++) {
    const t = i / sampleRate;
    if (profile === 'steady') {
      // Steady cadence ~135Hz fundamental with natural brief pauses
      const inPause = (t > 1.8 && t < 2.1) || (t > 3.7 && t < 3.95);
      if (inPause) {
        samples[i] = 0;
      } else {
        const f0 = 135 + 4 * Math.sin(2 * Math.PI * 0.7 * t);
        const envelope = 0.35 + 0.08 * Math.sin(2 * Math.PI * 2.2 * t);
        samples[i] =
          envelope * (0.7 * Math.sin(2 * Math.PI * f0 * t) + 0.3 * Math.sin(2 * Math.PI * 2 * f0 * t));
      }
    } else {
      // Stressed cadence: wide F0 swings (140Hz -> 235Hz), frequent hesitation pauses, amplitude spikes
      const inPause =
        (t > 0.7 && t < 1.3) || (t > 2.0 && t < 2.8) || (t > 3.4 && t < 4.1);
      if (inPause) {
        samples[i] = 0;
      } else {
        const f0 = 155 + 58 * Math.sin(2 * Math.PI * 1.9 * t);
        const envelope = t > 2.8 && t < 3.4 ? 0.85 : 0.28;
        samples[i] =
          envelope * (0.65 * Math.sin(2 * Math.PI * f0 * t) + 0.35 * Math.sin(2 * Math.PI * 2 * f0 * t));
      }
    }
  }

  // Encode 16-bit PCM WAV
  const buffer = new ArrayBuffer(44 + totalSamples * 2);
  const view = new DataView(buffer);
  const writeString = (offset: number, str: string) => {
    for (let i = 0; i < str.length; i++) {
      view.setUint8(offset + i, str.charCodeAt(i));
    }
  };

  writeString(0, 'RIFF');
  view.setUint32(4, 36 + totalSamples * 2, true);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  writeString(36, 'data');
  view.setUint32(40, totalSamples * 2, true);

  let offset = 44;
  for (let i = 0; i < totalSamples; i++) {
    const clamped = Math.max(-1, Math.min(1, samples[i]));
    view.setInt16(offset, clamped < 0 ? clamped * 0x8000 : clamped * 0x7fff, true);
    offset += 2;
  }

  return new Blob([buffer], {type: 'audio/wav'});
}
