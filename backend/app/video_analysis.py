import cv2
import numpy as np
from scipy.signal import butter, filtfilt


def _estimate_rppg_bpm(green_series: list[float], sample_rate: float) -> tuple[float, float]:
    """Extract facial rPPG heart rate (BPM) & signal quality from skin green-channel variations."""
    if len(green_series) < 16 or sample_rate < 4.0:
        return 74.0, 0.25

    sig = np.asarray(green_series, dtype=np.float64)
    sig = sig - np.mean(sig)
    if np.std(sig) < 1e-5:
        return 74.0, 0.15

    nyq = 0.5 * sample_rate
    low = max(0.05, 0.75 / nyq)
    high = min(0.95, 2.8 / nyq)
    if low >= high:
        return 74.0, 0.25

    try:
        b, a = butter(2, [low, high], btype="band")
        filtered = filtfilt(b, a, sig)
    except Exception:
        filtered = sig

    fft_vals = np.abs(np.fft.rfft(filtered * np.hanning(len(filtered))))
    freqs = np.fft.rfftfreq(len(filtered), d=1.0 / sample_rate)
    mask = (freqs >= 0.8) & (freqs <= 2.6)
    if not np.any(mask):
        return 74.0, 0.25

    band_fft = fft_vals[mask]
    band_freqs = freqs[mask]
    peak_idx = int(np.argmax(band_fft))
    peak_freq = float(band_freqs[peak_idx])
    bpm = round(max(52.0, min(145.0, peak_freq * 60.0)), 1)
    snr = float(band_fft[peak_idx] / (np.mean(band_fft) + 1e-6))
    quality = round(min(1.0, max(0.1, (snr - 1.0) / 3.5)), 2)
    return bpm, quality


def analyze_video(video_path: str) -> dict:
    """Extract 14 ocular, micro-expression, physiological (rPPG), kinesic, and face liveness/deepfake indicators."""
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return _empty_video_metrics()

    fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    duration_sec = round(total_frames / fps, 2) if fps > 0 and total_frames > 0 else 0.0

    face_cascade = cv2.CascadeClassifier(
        cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    )
    eye_cascade = cv2.CascadeClassifier(
        cv2.data.haarcascades + "haarcascade_eye.xml"
    )

    target_hz = 8.0
    sample_stride = max(1, int(round(fps / target_hz)))
    eff_sample_rate = fps / sample_stride

    prev_gray = None
    prev_subchin = None
    prev_left_shoulder = None
    prev_right_shoulder = None

    frame_idx = 0
    analyzed = 0
    face_frames = 0

    # Ocular trackers
    blink_transitions = 0
    prev_eyes_open = True
    closed_run_frames = 0
    blink_durations_ms: list[float] = []
    iris_ratios: list[float] = []
    gaze_xs: list[float] = []
    gaze_ys: list[float] = []

    # Micro-expression trackers
    lip_ratios: list[float] = []
    brow_asymmetries: list[float] = []
    nostril_vars: list[float] = []
    duping_delight_flashes = 0

    # Physiological & Kinesic trackers
    green_means: list[float] = []
    head_centers: list[tuple[float, float]] = []
    motion_deltas: list[float] = []
    shoulder_asym_deltas: list[float] = []
    hand_adaptor_frames = 0
    larynx_motion_spikes = 0

    # Liveness / Deepfake trackers
    skin_sharpness_vals: list[float] = []
    boundary_artifact_vals: list[float] = []

    timeline = []
    av_activation_times: list[float] = []

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        if frame_idx % sample_stride == 0:
            analyzed += 1
            timestamp = round(frame_idx / fps, 2)
            small_bgr = cv2.resize(frame, (320, 240))
            small_gray = cv2.cvtColor(small_bgr, cv2.COLOR_BGR2GRAY)

            faces = face_cascade.detectMultiScale(
                small_gray, scaleFactor=1.15, minNeighbors=4, minSize=(44, 44)
            )
            face_present = len(faces) > 0

            delta_val = 0.0
            if prev_gray is not None:
                diff = cv2.absdiff(small_gray, prev_gray)
                delta_val = float(np.mean(diff))
                motion_deltas.append(delta_val)
            prev_gray = small_gray

            if face_present:
                face_frames += 1
                x, y, w, h = sorted(faces, key=lambda b: b[2] * b[3], reverse=True)[0]
                cx, cy = (x + w * 0.5) / 320.0, (y + h * 0.5) / 240.0
                head_centers.append((cx, cy))

                # 9. rPPG facial cheek/forehead skin green channel
                fx1, fx2 = x + int(w * 0.22), x + int(w * 0.78)
                fy1, fy2 = y + int(h * 0.14), y + int(h * 0.55)
                skin_roi = small_bgr[fy1:fy2, fx1:fx2]
                if skin_roi.size > 0:
                    green_means.append(float(np.mean(skin_roi[:, :, 1])))
                    # Deepfake skin texture sharpness (Laplacian variance)
                    skin_gray = cv2.cvtColor(skin_roi, cv2.COLOR_BGR2GRAY)
                    skin_sharpness_vals.append(float(cv2.Laplacian(skin_gray, cv2.CV_64F).var()))

                # Deepfake boundary artifact check (inner edge vs outer border gradient ratio)
                bx1, by1 = max(0, x - 6), max(0, y - 6)
                bx2, by2 = min(320, x + w + 6), min(240, y + h + 6)
                border_patch = small_gray[by1:by2, bx1:bx2]
                if border_patch.size > 0:
                    gx = cv2.Sobel(border_patch, cv2.CV_64F, 1, 0, ksize=3)
                    gy = cv2.Sobel(border_patch, cv2.CV_64F, 0, 1, ksize=3)
                    boundary_artifact_vals.append(float(np.mean(np.hypot(gx, gy))))

                # 1-4. Ocular metrics (Blink rate, Blink duration, Pupil/Iris ratio, Gaze shift)
                eye_roi = small_gray[y + int(h * 0.18) : y + int(h * 0.56), x : x + w]
                eyes = (
                    eye_cascade.detectMultiScale(eye_roi, scaleFactor=1.1, minNeighbors=3, minSize=(12, 12))
                    if eye_roi.size > 0
                    else ()
                )
                eyes_open = len(eyes) >= 1
                if prev_eyes_open and not eyes_open:
                    blink_transitions += 1
                    closed_run_frames = 1
                elif not eyes_open:
                    closed_run_frames += 1
                elif not prev_eyes_open and eyes_open:
                    if closed_run_frames > 0:
                        blink_durations_ms.append((closed_run_frames / eff_sample_rate) * 1000.0)
                    closed_run_frames = 0
                prev_eyes_open = eyes_open

                if len(eyes) >= 1:
                    ex, ey, ew, eh = eyes[0]
                    e_patch = eye_roi[ey : ey + eh, ex : ex + ew]
                    if e_patch.size > 0:
                        dark_thresh = np.percentile(e_patch, 22)
                        dark_mask = e_patch <= dark_thresh
                        iris_ratios.append(float(np.mean(dark_mask)))
                        ys_idx, xs_idx = np.where(dark_mask)
                        if len(xs_idx) > 0:
                            gaze_xs.append(float(np.mean(xs_idx) / max(1, ew)))
                            gaze_ys.append(float(np.mean(ys_idx) / max(1, eh)))

                # 5. Lip compression & 8. Duping delight (asymmetric brief smile flash)
                mouth_roi = small_gray[y + int(h * 0.65) : y + int(h * 0.94), x + int(w * 0.2) : x + int(w * 0.8)]
                if mouth_roi.size > 16:
                    mh, mw = mouth_roi.shape
                    edges_m = cv2.Canny(mouth_roi, 40, 120)
                    row_energy = np.mean(edges_m, axis=1)
                    active_rows = int(np.sum(row_energy > np.mean(row_energy) * 0.8))
                    lip_ratio = active_rows / max(1.0, float(mw))
                    lip_ratios.append(lip_ratio)
                    left_corner = float(np.mean(edges_m[: mh // 2, : mw // 3]))
                    right_corner = float(np.mean(edges_m[: mh // 2, (2 * mw) // 3 :]))
                    asym = abs(left_corner - right_corner)
                    if asym > 18.0:
                        duping_delight_flashes += 1
                        av_activation_times.append(timestamp)

                # 6. Eyebrow asymmetry
                brow_roi = small_gray[y + int(h * 0.10) : y + int(h * 0.30), x + int(w * 0.12) : x + int(w * 0.88)]
                if brow_roi.size > 16:
                    bw = brow_roi.shape[1]
                    left_b = float(np.std(brow_roi[:, : bw // 2]))
                    right_b = float(np.std(brow_roi[:, bw // 2 :]))
                    brow_asymmetries.append(abs(left_b - right_b) / (left_b + right_b + 1e-4))

                # 7. Nostril flare
                nose_roi = small_gray[y + int(h * 0.45) : y + int(h * 0.68), x + int(w * 0.30) : x + int(w * 0.70)]
                if nose_roi.size > 16:
                    nostril_vars.append(float(np.std(nose_roi)))

                # 12. Shoulder shrug asymmetry (below face, left vs right)
                sy1, sy2 = min(238, y + h), min(240, y + int(h * 1.45))
                if sy2 - sy1 > 8:
                    l_sh = small_gray[sy1:sy2, max(0, x - int(w * 0.5)) : x + int(w * 0.2)]
                    r_sh = small_gray[sy1:sy2, x + int(w * 0.8) : min(320, x + int(w * 1.5))]
                    if (
                        prev_left_shoulder is not None
                        and prev_right_shoulder is not None
                        and l_sh.shape == prev_left_shoulder.shape
                        and r_sh.shape == prev_right_shoulder.shape
                        and l_sh.size > 0
                        and r_sh.size > 0
                    ):
                        dl = float(np.mean(cv2.absdiff(l_sh, prev_left_shoulder)))
                        dr = float(np.mean(cv2.absdiff(r_sh, prev_right_shoulder)))
                        shoulder_asym_deltas.append(abs(dl - dr))
                    prev_left_shoulder = l_sh.copy() if l_sh.size > 0 else None
                    prev_right_shoulder = r_sh.copy() if r_sh.size > 0 else None

                # 13. Hand-to-face self-adaptors (sudden skin-tone occlusion around lower cheek/mouth)
                hsv_face = cv2.cvtColor(
                    small_bgr[y + int(h * 0.55) : min(240, y + int(h * 1.05)), max(0, x - 8) : min(320, x + w + 8)],
                    cv2.COLOR_BGR2HSV,
                )
                if hsv_face.size > 0 and delta_val > 7.5:
                    skin_mask = cv2.inRange(hsv_face, np.array([0, 30, 60]), np.array([25, 190, 255]))
                    if float(np.mean(skin_mask > 0)) > 0.62:
                        hand_adaptor_frames += 1

                # 14. Swallowing / Larynx motion below chin
                cy1, cy2 = min(238, y + h), min(240, y + int(h * 1.32))
                cx1, cx2 = x + int(w * 0.25), x + int(w * 0.75)
                subchin = small_gray[cy1:cy2, cx1:cx2]
                if subchin.size > 16:
                    if prev_subchin is not None and prev_subchin.shape == subchin.shape:
                        larynx_diff = float(np.mean(cv2.absdiff(subchin, prev_subchin)))
                        if larynx_diff > 9.0:
                            larynx_motion_spikes += 1
                    prev_subchin = subchin.copy()

            timeline.append(
                {
                    "t": timestamp,
                    "motion": round(min(100.0, delta_val * 4.0), 1),
                    "face_detected": face_present,
                }
            )

        frame_idx += 1

    cap.release()

    if duration_sec == 0.0 and analyzed > 0:
        duration_sec = round(frame_idx / fps, 2)

    minutes = max(duration_sec / 60.0, 1.0 / 60.0)
    face_ratio = round((face_frames / analyzed) * 100.0, 1) if analyzed > 0 else 0.0
    blink_rate = round(blink_transitions / minutes, 1)
    blink_duration_ms = round(float(np.mean(blink_durations_ms)), 1) if blink_durations_ms else 185.0
    pupil_dilation = round(float(np.mean(iris_ratios)) * 100.0, 1) if iris_ratios else 24.0

    gaze_std_x = float(np.std(gaze_xs)) if len(gaze_xs) > 2 else 0.04
    gaze_std_y = float(np.std(gaze_ys)) if len(gaze_ys) > 2 else 0.03
    gaze_instability = round(min(100.0, max(0.0, (gaze_std_x + gaze_std_y) - 0.06) * 200.0), 1)
    mean_gx = float(np.mean(gaze_xs)) if gaze_xs else 0.5
    gaze_dir = "Left (Recall)" if mean_gx < 0.44 else "Right (Construct)" if mean_gx > 0.56 else "Center (Direct)"

    avg_lip = float(np.mean(lip_ratios)) if lip_ratios else 0.25
    lip_compression = round(min(100.0, max(0.0, (0.28 - avg_lip) * 140.0)), 1)
    eyebrow_asym = round(min(100.0, max(0.0, (float(np.mean(brow_asymmetries)) if brow_asymmetries else 0.07) - 0.07) * 150.0), 1)
    nostril_flare = round(min(100.0, max(0.0, (float(np.std(nostril_vars)) if len(nostril_vars) > 2 else 1.8) - 1.5) * 6.5), 1)

    rppg_bpm, rppg_quality = _estimate_rppg_bpm(green_means, eff_sample_rate)

    if len(head_centers) > 2:
        xs = [p[0] for p in head_centers]
        ys = [p[1] for p in head_centers]
        head_jitter = round(min(100.0, max(0.0, (float(np.std(xs)) + float(np.std(ys))) - 0.022) * 420.0), 1)
    else:
        head_jitter = 14.0

    avg_motion = float(np.mean(motion_deltas)) if motion_deltas else 0.0
    std_motion = float(np.std(motion_deltas)) if motion_deltas else 0.0
    # Subtract natural handheld smartphone shake floor before penalizing sudden jerky motion
    motion_jitter = round(
        min(100.0, max(0.0, std_motion - 1.6) * 4.4 + max(0.0, avg_motion - 4.5) * 1.6),
        1,
    )

    # Postural freeze: abnormally low upper-body motion (<1.8 mean pixel diff while face present)
    postural_freeze = round(min(100.0, max(0.0, (2.6 - avg_motion) * 22.0)), 1) if face_frames > 4 else 12.0
    shoulder_shrug = round(min(100.0, max(0.0, (float(np.mean(shoulder_asym_deltas)) if shoulder_asym_deltas else 1.2) - 1.0) * 6.5), 1)
    hand_adaptor_rate = round((hand_adaptor_frames / max(1, face_frames)) * 100.0, 1)

    # Media Authenticity: Face Liveness & Deepfake check
    sharpness = float(np.mean(skin_sharpness_vals)) if skin_sharpness_vals else 55.0
    boundary = float(np.mean(boundary_artifact_vals)) if boundary_artifact_vals else 24.0
    # Synthetic deepfakes often exhibit over-smoothed skin (low Laplacian variance <18) + weak rPPG + sharp boundary
    smooth_penalty = max(0.0, (24.0 - sharpness) * 1.4) if sharpness < 24.0 else 0.0
    boundary_penalty = max(0.0, (boundary - 58.0) * 0.7) if boundary > 58.0 else 0.0
    rppg_bonus = rppg_quality * 18.0
    real_human_pct = round(max(12.0, min(99.2, 84.0 + rppg_bonus - smooth_penalty - boundary_penalty)), 1)
    deepfake_risk_pct = round(100.0 - real_human_pct, 1)

    # Normal resting blink rate is 11-23/min; tolerate Haar indoor lighting noise up to ±6 blinks/min
    blink_rate_clamped = min(blink_rate, 48.0)
    blink_deviation = min(100.0, max(0.0, abs(blink_rate_clamped - 17.0) - 6.0) * 2.2) if face_frames > 0 else 18.0
    visual_stress = round(
        min(
            100.0,
            max(
                8.0,
                0.24 * motion_jitter
                + 0.20 * blink_deviation
                + 0.18 * gaze_instability
                + 0.14 * lip_compression
                + 0.12 * eyebrow_asym
                + 0.12 * head_jitter,
            ),
        ),
        1,
    )

    return {
        "duration_sec": duration_sec,
        "fps": round(fps, 1),
        "frames_analyzed": analyzed,
        "face_detected_ratio": face_ratio,
        # 1-8 Ocular & Micro-Expression
        "blink_rate_per_min": blink_rate,
        "blink_duration_ms": blink_duration_ms,
        "pupil_dilation_ratio": pupil_dilation,
        "gaze_instability_index": gaze_instability,
        "gaze_aversion_direction": gaze_dir,
        "lip_compression_index": lip_compression,
        "eyebrow_asymmetry_index": eyebrow_asym,
        "nostril_flare_index": nostril_flare,
        "duping_delight_flashes": duping_delight_flashes,
        # 9-14 Physiological & Kinesic
        "rppg_bpm": rppg_bpm,
        "rppg_signal_quality": rppg_quality,
        "head_jitter_index": head_jitter,
        "motion_jitter_index": motion_jitter,
        "postural_freeze_index": postural_freeze,
        "shoulder_shrug_asymmetry": shoulder_shrug,
        "hand_to_face_adaptors_pct": hand_adaptor_rate,
        "swallowing_larynx_spikes": larynx_motion_spikes,
        # Authenticity & sync
        "real_human_pct": real_human_pct,
        "deepfake_risk_pct": deepfake_risk_pct,
        "first_expression_sec": av_activation_times[0] if av_activation_times else round(duration_sec * 0.35, 2),
        "visual_stress_index": visual_stress,
        "timeline": timeline[:120],
    }


def _empty_video_metrics() -> dict:
    return {
        "duration_sec": 0.0,
        "fps": 0.0,
        "frames_analyzed": 0,
        "face_detected_ratio": 0.0,
        "blink_rate_per_min": 0.0,
        "blink_duration_ms": 0.0,
        "pupil_dilation_ratio": 0.0,
        "gaze_instability_index": 0.0,
        "gaze_aversion_direction": "Unknown",
        "lip_compression_index": 0.0,
        "eyebrow_asymmetry_index": 0.0,
        "nostril_flare_index": 0.0,
        "duping_delight_flashes": 0,
        "rppg_bpm": 74.0,
        "rppg_signal_quality": 0.0,
        "head_jitter_index": 0.0,
        "motion_jitter_index": 0.0,
        "postural_freeze_index": 0.0,
        "shoulder_shrug_asymmetry": 0.0,
        "hand_to_face_adaptors_pct": 0.0,
        "swallowing_larynx_spikes": 0,
        "real_human_pct": 50.0,
        "deepfake_risk_pct": 50.0,
        "first_expression_sec": 0.0,
        "visual_stress_index": 0.0,
        "timeline": [],
    }
