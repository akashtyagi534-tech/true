export interface VideoTimelinePoint {
  t: number;
  motion: number;
  face_detected: boolean;
}

export interface AudioTimelinePoint {
  t: number;
  energy: number;
  pitch_hz: number;
}

export interface VideoMetrics {
  duration_sec: number;
  fps: number;
  frames_analyzed: number;
  face_detected_ratio: number;
  blink_rate_per_min: number;
  motion_jitter_index: number;
  visual_stress_index: number;
  timeline: VideoTimelinePoint[];
}

export interface AudioMetrics {
  duration_sec: number;
  pitch_mean_hz: number;
  pitch_std_hz: number;
  energy_rms_mean: number;
  energy_spike_rate: number;
  pause_ratio: number;
  vocal_stress_index: number;
  audio_available: boolean;
  timeline: AudioTimelinePoint[];
}

export interface VerificationReport {
  consistency_index: number;
  combined_stress_index: number;
  classification: string;
  confidence: string;
  video: VideoMetrics;
  audio: AudioMetrics;
  findings: string[];
  disclaimer: string;
  sourceLabel?: string;
  analyzedAt?: string;
}

export interface RepoFile {
  path: string;
  content: string;
  size: number;
  lines: number;
  language: string;
}

export type AppSection = 'admin' | 'files' | 'guide' | 'lab' | 'architecture';
export type UiLanguage = 'hi' | 'en';
export type ProjectBundle = 'v3' | 'mobile';
