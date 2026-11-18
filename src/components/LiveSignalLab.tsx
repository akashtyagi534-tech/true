import {useEffect, useRef, useState} from 'react';
import {
  Camera,
  FileAudio,
  FileJson,
  Play,
  Square,
  Upload,
  Video,
  Waves,
} from 'lucide-react';
import type {UiLanguage, VerificationReport} from '../types/truthVerify';
import {
  analyzeMediaBlob,
  createCalibratedSpeechWavBlob,
} from '../utils/signalAnalyzer';

interface LiveSignalLabProps {
  railwayUrl: string;
  language: UiLanguage;
  onChangeLanguage: (lang: UiLanguage) => void;
}

type AnalysisMode = 'local' | 'railway';

export function LiveSignalLab({
  railwayUrl,
  language,
  onChangeLanguage,
}: LiveSignalLabProps) {
  const videoPreviewRef = useRef<HTMLVideoElement | null>(null);
  const mediaStreamRef = useRef<MediaStream | null>(null);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const [analysisMode, setAnalysisMode] = useState<AnalysisMode>('local');
  const [cameraActive, setCameraActive] = useState(false);
  const [isRecording, setIsRecording] = useState(false);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const [recordedBlob, setRecordedBlob] = useState<Blob | null>(null);
  const [recordedUrl, setRecordedUrl] = useState<string | null>(null);
  const [sourceName, setSourceName] = useState<string>('');
  const [isAnalyzing, setIsAnalyzing] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [report, setReport] = useState<VerificationReport | null>(null);

  useEffect(() => {
    if (!isRecording) return;
    const timer = window.setInterval(() => {
      setElapsedSeconds((prev) => prev + 1);
    }, 1000);
    return () => window.clearInterval(timer);
  }, [isRecording]);

  useEffect(() => {
    return () => {
      if (mediaStreamRef.current) {
        mediaStreamRef.current.getTracks().forEach((track) => track.stop());
      }
      if (recordedUrl) {
        URL.revokeObjectURL(recordedUrl);
      }
    };
  }, [recordedUrl]);

  const stopCameraTracks = () => {
    if (mediaStreamRef.current) {
      mediaStreamRef.current.getTracks().forEach((track) => track.stop());
      mediaStreamRef.current = null;
    }
    setCameraActive(false);
  };

  const handleEnableCamera = async () => {
    setErrorMessage(null);
    try {
      if (!navigator.mediaDevices?.getUserMedia) {
        throw new Error('Browser media capture API is unavailable in this context.');
      }
      const stream = await navigator.mediaDevices.getUserMedia({
        video: {width: {ideal: 640}, height: {ideal: 480}, facingMode: 'user'},
        audio: true,
      });
      mediaStreamRef.current = stream;
      setCameraActive(true);
      if (recordedUrl) {
        URL.revokeObjectURL(recordedUrl);
        setRecordedUrl(null);
      }
      setRecordedBlob(null);
      if (videoPreviewRef.current) {
        videoPreviewRef.current.srcObject = stream;
        videoPreviewRef.current.muted = true;
        await videoPreviewRef.current.play().catch(() => undefined);
      }
    } catch (err) {
      setErrorMessage(
        err instanceof Error
          ? err.message
          : 'Could not access camera or microphone permissions.',
      );
    }
  };

  const handleToggleRecording = () => {
    if (!mediaStreamRef.current) return;

    if (isRecording) {
      recorderRef.current?.stop();
      setIsRecording(false);
      return;
    }

    chunksRef.current = [];
    const preferredTypes = ['video/webm;codecs=vp8,opus', 'video/webm', 'video/mp4'];
    const mimeType = preferredTypes.find((t) => MediaRecorder.isTypeSupported(t));
    const recorder = mimeType
      ? new MediaRecorder(mediaStreamRef.current, {mimeType})
      : new MediaRecorder(mediaStreamRef.current);

    recorder.ondataavailable = (ev) => {
      if (ev.data.size > 0) chunksRef.current.push(ev.data);
    };
    recorder.onstop = () => {
      const blob = new Blob(chunksRef.current, {type: recorder.mimeType || 'video/webm'});
      const url = URL.createObjectURL(blob);
      setRecordedBlob(blob);
      setRecordedUrl(url);
      setSourceName(`camera-capture-${new Date().toISOString().slice(11, 19).replace(/:/g, '')}.webm`);
      stopCameraTracks();
      if (videoPreviewRef.current) {
        videoPreviewRef.current.srcObject = null;
        videoPreviewRef.current.src = url;
        videoPreviewRef.current.muted = false;
      }
    };

    recorderRef.current = recorder;
    setElapsedSeconds(0);
    setIsRecording(true);
    recorder.start(250);
  };

  const handleFileSelected = (file: File | undefined) => {
    if (!file) return;
    setErrorMessage(null);
    stopCameraTracks();
    if (recordedUrl) {
      URL.revokeObjectURL(recordedUrl);
    }
    const url = URL.createObjectURL(file);
    setRecordedBlob(file);
    setRecordedUrl(url);
    setSourceName(file.name);
    if (videoPreviewRef.current && !file.type.startsWith('audio/')) {
      videoPreviewRef.current.srcObject = null;
      videoPreviewRef.current.src = url;
      videoPreviewRef.current.muted = false;
    }
  };

  const handleRunAnalysis = async (blobToAnalyze?: Blob, labelOverride?: string) => {
    const targetBlob = blobToAnalyze ?? recordedBlob;
    const targetName = labelOverride ?? (sourceName || 'captured-clip.webm');
    if (!targetBlob) {
      setErrorMessage('Record a video clip or upload a media file first.');
      return;
    }

    setIsAnalyzing(true);
    setErrorMessage(null);
    try {
      if (analysisMode === 'railway') {
        const cleanBase = railwayUrl.trim().replace(/\/+$/, '');
        const formData = new FormData();
        formData.append('file', targetBlob, targetName);
        const resp = await fetch(`${cleanBase}/analyze`, {
          method: 'POST',
          body: formData,
        });
        if (!resp.ok) {
          const text = await resp.text();
          throw new Error(`Railway server returned HTTP ${resp.status}: ${text}`);
        }
        const json = (await resp.json()) as VerificationReport;
        setReport({
          ...json,
          sourceLabel: `${targetName} · Railway`,
          analyzedAt: new Date().toISOString(),
        });
      } else {
        const computed = await analyzeMediaBlob(targetBlob, `${targetName} · Browser DSP`);
        setReport(computed);
      }
    } catch (err) {
      setErrorMessage(
        err instanceof Error ? err.message : 'Signal analysis failed. Check media format or Railway URL.',
      );
    } finally {
      setIsAnalyzing(false);
    }
  };

  const handleGenerateCalibratedAudio = async (profile: 'steady' | 'stressed') => {
    stopCameraTracks();
    const wavBlob = createCalibratedSpeechWavBlob(profile);
    if (recordedUrl) URL.revokeObjectURL(recordedUrl);
    const url = URL.createObjectURL(wavBlob);
    const name = profile === 'steady' ? 'calibrated-steady-135hz.wav' : 'calibrated-variance-f0.wav';
    setRecordedBlob(wavBlob);
    setRecordedUrl(url);
    setSourceName(name);
    await handleRunAnalysis(wavBlob, name);
  };

  const handleExportReportJson = () => {
    if (!report) return;
    const blob = new Blob([JSON.stringify(report, null, 2)], {type: 'application/json'});
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `truthverify-report-${Date.now()}.json`;
    link.click();
    URL.revokeObjectURL(url);
  };

  const classificationTone = (score: number) => {
    if (score >= 72) return {text: 'text-emerald-700', bar: 'bg-emerald-600'};
    if (score >= 45) return {text: 'text-amber-700', bar: 'bg-amber-600'};
    return {text: 'text-red-700', bar: 'bg-red-600'};
  };

  const mergedTimeline = (() => {
    if (!report) return [];
    const maxLen = Math.max(report.video.timeline.length, report.audio.timeline.length);
    if (maxLen === 0) return [];
    const rows: Array<{t: number; motion: number; energy: number; pitch: number}> = [];
    for (let i = 0; i < Math.min(maxLen, 60); i++) {
      const v = report.video.timeline[i];
      const a = report.audio.timeline[i];
      rows.push({
        t: v?.t ?? a?.t ?? i,
        motion: v?.motion ?? 0,
        energy: a?.energy ?? 0,
        pitch: a?.pitch_hz ?? 0,
      });
    }
    return rows;
  })();

  const buildPolyline = (points: number[], width: number, height: number) => {
    if (points.length === 0) return '';
    if (points.length === 1) return `0,${height - (points[0] / 100) * height}`;
    return points
      .map((val, idx) => {
        const x = (idx / (points.length - 1)) * width;
        const clamped = Math.max(0, Math.min(100, val));
        const y = height - (clamped / 100) * (height - 12) - 6;
        return `${x.toFixed(1)},${y.toFixed(1)}`;
      })
      .join(' ');
  };

  return (
    <section className="mx-auto max-w-[1360px] px-6 py-8">
      <div className="mb-6 flex flex-wrap items-end justify-between gap-4 border-b border-slate-200 pb-6">
        <div className="max-w-2xl">
          <p className="text-xs font-medium text-slate-500">
            Multimodal Verification Workbench · Video & Acoustic DSP
          </p>
          <h1 className="mt-1.5 font-display text-2xl font-semibold tracking-tight text-slate-950 sm:text-3xl">
            {language === 'hi'
              ? 'लाइव वीडियो और ऑडियो सिग्नल विश्लेषण लैब'
              : 'Live Video & Acoustic Signal Verification Lab'}
          </h1>
          <p className="mt-2 text-sm leading-relaxed text-slate-600">
            {language === 'hi'
              ? 'कैमरे से रिकॉर्ड करें या वीडियो/ऑडियो फाइल अपलोड करके पिच (F0), पॉज़ अनुपात और मूवमेंट वेरिएंस की जाँच करें — ब्राउज़र में या अपने लाइव Railway सर्वर पर।'
              : 'Record from your webcam or upload a media clip to measure fundamental pitch variance (F0), pause ratio, and frame motion jitter locally or against your live Railway backend.'}
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-3">
          <div className="inline-flex items-center rounded-lg border border-slate-200 bg-slate-100 p-1">
            <button
              type="button"
              onClick={() => setAnalysisMode('local')}
              className={`rounded-md px-3 py-1.5 text-xs font-medium transition-colors whitespace-nowrap shrink-0 ${
                analysisMode === 'local'
                  ? 'bg-white text-slate-900 shadow-xs'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              Browser Engine
            </button>
            <button
              type="button"
              onClick={() => setAnalysisMode('railway')}
              className={`rounded-md px-3 py-1.5 text-xs font-medium transition-colors whitespace-nowrap shrink-0 ${
                analysisMode === 'railway'
                  ? 'bg-white text-slate-900 shadow-xs'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              Railway API
            </button>
          </div>

          <div className="inline-flex items-center rounded-lg border border-slate-200 bg-slate-100 p-1">
            <button
              type="button"
              onClick={() => onChangeLanguage('hi')}
              className={`rounded-md px-2.5 py-1.5 text-xs font-medium transition-colors whitespace-nowrap shrink-0 ${
                language === 'hi'
                  ? 'bg-white text-slate-900 shadow-xs'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              हिन्दी
            </button>
            <button
              type="button"
              onClick={() => onChangeLanguage('en')}
              className={`rounded-md px-2.5 py-1.5 text-xs font-medium transition-colors whitespace-nowrap shrink-0 ${
                language === 'en'
                  ? 'bg-white text-slate-900 shadow-xs'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              English
            </button>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-8 lg:grid-cols-12 lg:items-start">
        {/* Left Capture & Input Column */}
        <div className="space-y-6 lg:col-span-5">
          <div className="overflow-hidden rounded-xl border border-slate-200 bg-white">
            <div className="flex items-center justify-between border-b border-slate-200 px-5 py-3.5">
              <div className="flex items-center gap-2 text-sm font-medium text-slate-900">
                <Video className="h-4 w-4 text-slate-500" aria-hidden="true" />
                <span>Media Capture</span>
              </div>
              <span className="font-mono text-xs text-slate-500 tabular-nums">
                {isRecording
                  ? `REC ${String(Math.floor(elapsedSeconds / 60)).padStart(2, '0')}:${String(elapsedSeconds % 60).padStart(2, '0')}`
                  : sourceName || 'No clip loaded'}
              </span>
            </div>

            <div className="relative aspect-video w-full bg-slate-950">
              {recordedBlob?.type.startsWith('audio/') && recordedUrl ? (
                <div className="flex h-full flex-col items-center justify-center gap-4 px-6 text-center text-white">
                  <FileAudio className="h-8 w-8 text-slate-300" aria-hidden="true" />
                  <p className="font-mono text-xs text-slate-300">{sourceName}</p>
                  <audio controls src={recordedUrl} className="w-full max-w-sm" />
                </div>
              ) : (
                <video
                  ref={videoPreviewRef}
                  controls={Boolean(recordedUrl) && !cameraActive}
                  playsInline
                  className="h-full w-full object-cover"
                />
              )}

              {!cameraActive && !recordedUrl && (
                <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 px-6 text-center">
                  <Camera className="h-7 w-7 text-slate-500" aria-hidden="true" />
                  <p className="text-sm font-medium text-slate-200">
                    {language === 'hi'
                      ? 'कैमरा चालू करें या वीडियो/ऑडियो फाइल चुनें'
                      : 'Enable camera capture or upload a video/audio file'}
                  </p>
                  <p className="text-xs text-slate-400">
                    MP4, WebM, MOV, or WAV · Analyzed via {analysisMode === 'railway' ? railwayUrl : 'Web Audio + Canvas DSP'}
                  </p>
                </div>
              )}
            </div>

            <div className="flex flex-wrap items-center gap-3 border-t border-slate-200 p-4">
              {!cameraActive ? (
                <button
                  type="button"
                  onClick={handleEnableCamera}
                  className="inline-flex items-center gap-2 rounded-lg border border-slate-300 bg-white px-4 py-2 text-xs font-medium text-slate-900 transition-colors hover:bg-slate-50 whitespace-nowrap shrink-0"
                >
                  <Camera className="h-3.5 w-3.5" aria-hidden="true" />
                  <span>{language === 'hi' ? 'कैमरा चालू करें' : 'Enable Camera'}</span>
                </button>
              ) : (
                <button
                  type="button"
                  onClick={handleToggleRecording}
                  className={`inline-flex items-center gap-2 rounded-lg px-4 py-2 text-xs font-medium text-white transition-colors whitespace-nowrap shrink-0 ${
                    isRecording
                      ? 'bg-red-700 hover:bg-red-800'
                      : 'bg-blue-700 hover:bg-blue-800'
                  }`}
                >
                  {isRecording ? (
                    <>
                      <Square className="h-3.5 w-3.5" aria-hidden="true" />
                      <span>{language === 'hi' ? 'रिकॉर्डिंग रोकें' : 'Stop Recording'}</span>
                    </>
                  ) : (
                    <>
                      <Play className="h-3.5 w-3.5" aria-hidden="true" />
                      <span>{language === 'hi' ? 'रिकॉर्ड शुरू करें' : 'Start Recording'}</span>
                    </>
                  )}
                </button>
              )}

              <input
                ref={fileInputRef}
                type="file"
                accept="video/*,audio/*"
                className="hidden"
                onChange={(e) => handleFileSelected(e.target.files?.[0])}
              />
              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                className="inline-flex items-center gap-2 rounded-lg border border-slate-300 bg-white px-4 py-2 text-xs font-medium text-slate-700 transition-colors hover:bg-slate-50 whitespace-nowrap shrink-0"
              >
                <Upload className="h-3.5 w-3.5" aria-hidden="true" />
                <span>{language === 'hi' ? 'फ़ाइल अपलोड' : 'Upload Clip'}</span>
              </button>

              <button
                type="button"
                onClick={() => handleRunAnalysis()}
                disabled={!recordedBlob || isAnalyzing || isRecording}
                className="ml-auto inline-flex items-center gap-2 rounded-lg bg-blue-700 px-4 py-2 text-xs font-medium text-white transition-colors hover:bg-blue-800 disabled:cursor-not-allowed disabled:opacity-50 whitespace-nowrap shrink-0"
              >
                <Waves className="h-3.5 w-3.5" aria-hidden="true" />
                <span>
                  {isAnalyzing
                    ? language === 'hi'
                      ? 'विश्लेषण जारी...'
                      : 'Analyzing...'
                    : language === 'hi'
                      ? 'विश्लेषण करें'
                      : 'Run Analysis'}
                </span>
              </button>
            </div>
          </div>

          <div className="rounded-xl border border-slate-200 bg-white p-5">
            <h2 className="text-sm font-semibold text-slate-900">
              {language === 'hi' ? 'त्वरित कैलिब्रेटेड ऑडियो टेस्ट (16kHz PCM)' : 'Calibrated Acoustic Test Waveforms (16kHz PCM)'}
            </h2>
            <p className="mt-1 text-xs leading-relaxed text-slate-600">
              {language === 'hi'
                ? 'यदि अभी कैमरा उपलब्ध नहीं है, तो वास्तविक WAV वेवफॉर्म जेनरेट करके ऑडियो DSP पाइपलाइन टेस्ट करें।'
                : 'Synthesize real 16kHz WAV audio signals to inspect how the F0 pitch and pause-ratio analyzer responds.'}
            </p>
            <div className="mt-4 flex flex-wrap gap-3">
              <button
                type="button"
                onClick={() => handleGenerateCalibratedAudio('steady')}
                disabled={isAnalyzing}
                className="rounded-lg border border-slate-300 bg-white px-3.5 py-2 text-xs font-medium text-slate-800 transition-colors hover:bg-slate-50 whitespace-nowrap shrink-0"
              >
                Steady 135 Hz Cadence
              </button>
              <button
                type="button"
                onClick={() => handleGenerateCalibratedAudio('stressed')}
                disabled={isAnalyzing}
                className="rounded-lg border border-slate-300 bg-white px-3.5 py-2 text-xs font-medium text-slate-800 transition-colors hover:bg-slate-50 whitespace-nowrap shrink-0"
              >
                High F0 Variance + Pauses
              </button>
            </div>
          </div>

          {errorMessage && (
            <div role="alert" className="rounded-xl border border-red-200 bg-red-50 p-4 text-xs text-red-800">
              {errorMessage}
            </div>
          )}
        </div>

        {/* Right Report Output Column */}
        <div className="lg:col-span-7">
          {!report ? (
            <div className="flex min-h-[460px] flex-col items-center justify-center rounded-xl border border-slate-200 bg-white p-10 text-center">
              <Waves className="h-8 w-8 text-slate-300" aria-hidden="true" />
              <h2 className="mt-4 font-display text-lg font-semibold text-slate-900">
                {language === 'hi' ? 'रिपोर्ट प्रतीक्षा में है' : 'Awaiting Signal Analysis'}
              </h2>
              <p className="mt-2 max-w-md text-sm text-slate-600">
                {language === 'hi'
                  ? 'बाईं ओर से वीडियो रिकॉर्ड करें, फाइल अपलोड करें, या कैलिब्रेटेड ऑडियो टेस्ट चलाकर पूरा स्कोरिंग और टाइमलाइन चार्ट देखें।'
                  : 'Capture a clip, upload media, or run a calibrated PCM waveform on the left to inspect consistency scoring, vocal F0 metrics, and frame timeline curves.'}
              </p>
            </div>
          ) : (
            <div className="rounded-xl border border-slate-200 bg-white">
              <div className="flex flex-wrap items-center justify-between gap-4 border-b border-slate-200 px-6 py-4">
                <div>
                  <p className="text-xs text-slate-500">
                    {report.sourceLabel} · Confidence: {report.confidence}
                  </p>
                  <h2 className={`mt-1 font-display text-xl font-semibold ${classificationTone(report.consistency_index).text}`}>
                    {report.classification}
                  </h2>
                </div>
                <button
                  type="button"
                  onClick={handleExportReportJson}
                  className="inline-flex items-center gap-2 rounded-lg border border-slate-300 bg-white px-3.5 py-2 text-xs font-medium text-slate-800 transition-colors hover:bg-slate-50 whitespace-nowrap shrink-0"
                >
                  <FileJson className="h-3.5 w-3.5" aria-hidden="true" />
                  <span>Export JSON</span>
                </button>
              </div>

              {/* Primary Index Strip */}
              <div className="grid grid-cols-2 divide-x divide-y divide-slate-200 border-b border-slate-200 sm:grid-cols-4 sm:divide-y-0">
                <div className="p-5">
                  <p className="text-xs text-slate-500">Consistency Index</p>
                  <p className="mt-1.5 font-mono text-2xl font-semibold text-slate-950 tabular-nums">
                    {report.consistency_index.toFixed(1)}
                    <span className="text-sm font-normal text-slate-400"> / 100</span>
                  </p>
                </div>
                <div className="p-5">
                  <p className="text-xs text-slate-500">Combined Stress</p>
                  <p className="mt-1.5 font-mono text-2xl font-semibold text-slate-950 tabular-nums">
                    {report.combined_stress_index.toFixed(1)}%
                  </p>
                </div>
                <div className="p-5">
                  <p className="text-xs text-slate-500">Visual Stress</p>
                  <p className="mt-1.5 font-mono text-2xl font-semibold text-slate-950 tabular-nums">
                    {report.video.visual_stress_index.toFixed(1)}%
                  </p>
                </div>
                <div className="p-5">
                  <p className="text-xs text-slate-500">Vocal Stress</p>
                  <p className="mt-1.5 font-mono text-2xl font-semibold text-slate-950 tabular-nums">
                    {report.audio.vocal_stress_index.toFixed(1)}%
                  </p>
                </div>
              </div>

              {/* Timeline Chart */}
              {mergedTimeline.length > 1 && (
                <div className="border-b border-slate-200 p-6">
                  <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                    <h3 className="text-sm font-semibold text-slate-900">
                      Temporal Signal Curve
                    </h3>
                    <div className="flex items-center gap-4 text-xs text-slate-600">
                      <span className="inline-flex items-center gap-1.5">
                        <span className="inline-block h-2 w-4 bg-blue-700" aria-hidden="true" />
                        Vocal Energy (%)
                      </span>
                      <span className="inline-flex items-center gap-1.5">
                        <span className="inline-block h-2 w-4 bg-amber-600" aria-hidden="true" />
                        Visual Motion (%)
                      </span>
                    </div>
                  </div>
                  <div className="overflow-hidden rounded-lg border border-slate-200 bg-slate-50 p-3">
                    <svg
                      viewBox="0 0 600 140"
                      className="h-36 w-full"
                      role="img"
                      aria-label="Vocal energy and visual motion over recording duration"
                    >
                      <line x1="0" y1="35" x2="600" y2="35" stroke="#e2e8f0" strokeDasharray="4 4" />
                      <line x1="0" y1="70" x2="600" y2="70" stroke="#e2e8f0" strokeDasharray="4 4" />
                      <line x1="0" y1="105" x2="600" y2="105" stroke="#e2e8f0" strokeDasharray="4 4" />
                      <polyline
                        fill="none"
                        stroke="#1d4ed8"
                        strokeWidth="2.2"
                        points={buildPolyline(
                          mergedTimeline.map((p) => p.energy),
                          600,
                          140,
                        )}
                      />
                      <polyline
                        fill="none"
                        stroke="#d97706"
                        strokeWidth="2"
                        points={buildPolyline(
                          mergedTimeline.map((p) => p.motion),
                          600,
                          140,
                        )}
                      />
                    </svg>
                  </div>
                </div>
              )}

              {/* Dense Metric Table */}
              <div className="border-b border-slate-200 px-6 py-5">
                <h3 className="mb-3 text-sm font-semibold text-slate-900">
                  Extracted Telemetry Breakdown
                </h3>
                <div className="overflow-x-auto">
                  <table className="w-full text-left text-xs">
                    <thead>
                      <tr className="border-b border-slate-200 text-slate-500">
                        <th className="py-2 font-medium">Channel</th>
                        <th className="py-2 font-medium">Signal Metric</th>
                        <th className="py-2 text-right font-medium">Measured Value</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-100 text-slate-800">
                      <tr>
                        <td className="py-2.5 text-slate-500">Audio</td>
                        <td className="py-2.5">Mean Fundamental Pitch (F0)</td>
                        <td className="py-2.5 text-right font-mono tabular-nums">
                          {report.audio.pitch_mean_hz.toFixed(1)} Hz
                        </td>
                      </tr>
                      <tr>
                        <td className="py-2.5 text-slate-500">Audio</td>
                        <td className="py-2.5">Pitch Standard Deviation</td>
                        <td className="py-2.5 text-right font-mono tabular-nums">
                          {report.audio.pitch_std_hz.toFixed(1)} Hz
                        </td>
                      </tr>
                      <tr>
                        <td className="py-2.5 text-slate-500">Audio</td>
                        <td className="py-2.5">Silence / Hesitation Ratio</td>
                        <td className="py-2.5 text-right font-mono tabular-nums">
                          {report.audio.pause_ratio.toFixed(1)}%
                        </td>
                      </tr>
                      <tr>
                        <td className="py-2.5 text-slate-500">Audio</td>
                        <td className="py-2.5">Energy Spike Rate</td>
                        <td className="py-2.5 text-right font-mono tabular-nums">
                          {report.audio.energy_spike_rate.toFixed(1)}%
                        </td>
                      </tr>
                      <tr>
                        <td className="py-2.5 text-slate-500">Video</td>
                        <td className="py-2.5">Subject / Face Visibility Ratio</td>
                        <td className="py-2.5 text-right font-mono tabular-nums">
                          {report.video.face_detected_ratio.toFixed(1)}%
                        </td>
                      </tr>
                      <tr>
                        <td className="py-2.5 text-slate-500">Video</td>
                        <td className="py-2.5">Motion Jitter Index</td>
                        <td className="py-2.5 text-right font-mono tabular-nums">
                          {report.video.motion_jitter_index.toFixed(1)}%
                        </td>
                      </tr>
                      <tr>
                        <td className="py-2.5 text-slate-500">Video</td>
                        <td className="py-2.5">Estimated Blink Frequency</td>
                        <td className="py-2.5 text-right font-mono tabular-nums">
                          {report.video.blink_rate_per_min.toFixed(1)} / min
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>

              {/* Findings & Disclaimer */}
              <div className="p-6">
                <h3 className="text-sm font-semibold text-slate-900">Observed Indicators</h3>
                <ul className="mt-2.5 space-y-2 text-sm text-slate-700">
                  {report.findings.map((finding, idx) => (
                    <li key={idx} className="flex items-start gap-2.5">
                      <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-slate-400" aria-hidden="true" />
                      <span>{finding}</span>
                    </li>
                  ))}
                </ul>
                <p className="mt-4 text-xs leading-relaxed text-slate-500">
                  {report.disclaimer}
                </p>
              </div>
            </div>
          )}
        </div>
      </div>
    </section>
  );
}
