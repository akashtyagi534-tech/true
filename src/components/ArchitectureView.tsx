import type {UiLanguage} from '../types/truthVerify';

interface ArchitectureViewProps {
  railwayUrl: string;
  language: UiLanguage;
  onChangeLanguage: (lang: UiLanguage) => void;
}

const SAMPLE_RESPONSE = `{
  "consistency_index": 78.4,
  "combined_stress_index": 21.6,
  "classification": "Low Stress / Consistent",
  "confidence": "High",
  "video": {
    "duration_sec": 8.4,
    "fps": 30.0,
    "frames_analyzed": 50,
    "face_detected_ratio": 94.0,
    "blink_rate_per_min": 18.2,
    "motion_jitter_index": 19.4,
    "visual_stress_index": 15.8
  },
  "audio": {
    "duration_sec": 8.4,
    "pitch_mean_hz": 146.2,
    "pitch_std_hz": 14.8,
    "energy_rms_mean": 0.0412,
    "energy_spike_rate": 4.2,
    "pause_ratio": 24.5,
    "vocal_stress_index": 26.3,
    "audio_available": true
  }
}`;

export function ArchitectureView({
  railwayUrl,
  language,
  onChangeLanguage,
}: ArchitectureViewProps) {
  return (
    <section className="mx-auto max-w-[1360px] px-6 py-8">
      <div className="mb-8 flex flex-wrap items-end justify-between gap-4 border-b border-slate-200 pb-6">
        <div className="max-w-2xl">
          <p className="text-xs font-medium text-slate-500">
            System Design · Mobile Client + Railway Container + GitHub CI
          </p>
          <h1 className="mt-1.5 font-display text-2xl font-semibold tracking-tight text-slate-950 sm:text-3xl">
            {language === 'hi'
              ? 'एंड-टू-एंड सिस्टम आर्किटेक्चर और API स्कीमा'
              : 'End-to-End Pipeline Architecture & API Contract'}
          </h1>
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

      {/* 3-Stage Flow */}
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <div className="rounded-xl border border-slate-200 bg-white p-6">
          <p className="font-mono text-xs text-slate-500">01 · flutter_app/</p>
          <h2 className="mt-2 font-display text-lg font-semibold text-slate-950">
            Android Mobile Client
          </h2>
          <p className="mt-2 text-sm leading-relaxed text-slate-600">
            {language === 'hi'
              ? 'recording_screen.dart फ्रंट/रियर कैमरे व माइक्रोफोन से वीडियो रिकॉर्ड करता है और api_service.dart के ज़रिए मल्टीपार्ट POST अनुरोध भेजता है।'
              : 'recording_screen.dart captures synchronized camera video and microphone audio, then uploads multipart form data via api_service.dart.'}
          </p>
          <dl className="mt-5 divide-y divide-slate-100 border-t border-slate-200 text-xs">
            <div className="flex justify-between py-2.5">
              <dt className="text-slate-500">Target Endpoint</dt>
              <dd className="truncate font-mono text-slate-900">{railwayUrl}</dd>
            </div>
            <div className="flex justify-between py-2.5">
              <dt className="text-slate-500">Permissions</dt>
              <dd className="font-mono text-slate-900">INTERNET · CAMERA · AUDIO</dd>
            </div>
          </dl>
        </div>

        <div className="rounded-xl border border-slate-200 bg-white p-6">
          <p className="font-mono text-xs text-slate-500">02 · backend/</p>
          <h2 className="mt-2 font-display text-lg font-semibold text-slate-950">
            Railway Docker + FastAPI
          </h2>
          <p className="mt-2 text-sm leading-relaxed text-slate-600">
            {language === 'hi'
              ? 'ffmpeg वीडियो से 16kHz PCM ऑडियो निकालता है। video_analysis.py (OpenCV) और audio_analysis.py (librosa) समानांतर मीट्रिक निकालकर scoring.py को देते हैं।'
              : 'ffmpeg demuxes 16kHz mono PCM audio while OpenCV analyzes facial/motion jitter and librosa computes YIN F0 pitch and energy volatility.'}
          </p>
          <dl className="mt-5 divide-y divide-slate-100 border-t border-slate-200 text-xs">
            <div className="flex justify-between py-2.5">
              <dt className="text-slate-500">Base Image</dt>
              <dd className="font-mono text-slate-900">python:3.10-slim + ffmpeg</dd>
            </div>
            <div className="flex justify-between py-2.5">
              <dt className="text-slate-500">Scoring Weights</dt>
              <dd className="font-mono text-slate-900 tabular-nums">45% Visual · 55% Vocal</dd>
            </div>
          </dl>
        </div>

        <div className="rounded-xl border border-slate-200 bg-white p-6">
          <p className="font-mono text-xs text-slate-500">03 · .github/workflows/</p>
          <h2 className="mt-2 font-display text-lg font-semibold text-slate-950">
            Cloud APK Pipeline
          </h2>
          <p className="mt-2 text-sm leading-relaxed text-slate-600">
            {language === 'hi'
              ? 'main ब्रांच पर पुश होते ही Ubuntu रनर Java 17 व Flutter stable इंस्टॉल कर android/ जेनरेट करता है और app-release.apk आर्टिफैक्ट अपलोड करता है।'
              : 'On push to main/master, GitHub Actions provisions Java 17 + Flutter stable, injects Android manifest permissions, and publishes app-release.apk.'}
          </p>
          <dl className="mt-5 divide-y divide-slate-100 border-t border-slate-200 text-xs">
            <div className="flex justify-between py-2.5">
              <dt className="text-slate-500">Runner</dt>
              <dd className="font-mono text-slate-900">ubuntu-latest · JDK 17</dd>
            </div>
            <div className="flex justify-between py-2.5">
              <dt className="text-slate-500">Artifact Name</dt>
              <dd className="font-mono text-slate-900">TruthVerify-Release-APK</dd>
            </div>
          </dl>
        </div>
      </div>

      {/* API Payload Contract */}
      <div className="mt-8 overflow-hidden rounded-xl border border-slate-200 bg-white">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-200 px-6 py-4">
          <h2 className="font-display text-base font-semibold text-slate-950">
            POST /analyze Response Schema
          </h2>
          <span className="font-mono text-xs text-slate-500">
            multipart/form-data (field: file) → application/json
          </span>
        </div>
        <div className="bg-slate-950 p-6">
          <pre className="overflow-x-auto font-mono text-xs leading-6 text-slate-100">
            <code>{SAMPLE_RESPONSE}</code>
          </pre>
        </div>
      </div>
    </section>
  );
}
