import cv2
import numpy as np


def analyze_video(video_path: str) -> dict:
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return {
            "duration_sec": 0.0,
            "fps": 0.0,
            "frames_analyzed": 0,
            "face_detected_ratio": 0.0,
            "blink_rate_per_min": 0.0,
            "motion_jitter_index": 0.0,
            "visual_stress_index": 0.0,
            "timeline": [],
        }

    fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    duration_sec = round(total_frames / fps, 2) if fps > 0 and total_frames > 0 else 0.0

    face_cascade = cv2.CascadeClassifier(
        cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    )
    eye_cascade = cv2.CascadeClassifier(
        cv2.data.haarcascades + "haarcascade_eye.xml"
    )

    sample_stride = max(1, int(round(fps / 6)))  # ~6 samples per second
    prev_gray = None
    frame_idx = 0
    analyzed = 0
    face_frames = 0
    blink_transitions = 0
    prev_eyes_open = True

    motion_deltas = []
    timeline = []

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        if frame_idx % sample_stride == 0:
            analyzed += 1
            timestamp = round(frame_idx / fps, 2)
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            small = cv2.resize(gray, (320, 240))

            faces = face_cascade.detectMultiScale(small, scaleFactor=1.15, minNeighbors=4, minSize=(40, 40))
            face_present = len(faces) > 0
            if face_present:
                face_frames += 1
                x, y, w, h = faces[0]
                roi_gray = small[y : y + int(h * 0.6), x : x + w]
                eyes = eye_cascade.detectMultiScale(roi_gray, scaleFactor=1.1, minNeighbors=3, minSize=(12, 12))
                eyes_open = len(eyes) >= 1
                if prev_eyes_open and not eyes_open:
                    blink_transitions += 1
                prev_eyes_open = eyes_open

            delta_val = 0.0
            if prev_gray is not None:
                diff = cv2.absdiff(small, prev_gray)
                delta_val = float(np.mean(diff))
                motion_deltas.append(delta_val)

            prev_gray = small
            timeline.append({
                "t": timestamp,
                "motion": round(min(100.0, delta_val * 4.0), 1),
                "face_detected": face_present,
            })

        frame_idx += 1

    cap.release()

    if duration_sec == 0.0 and analyzed > 0:
        duration_sec = round((frame_idx / fps), 2)

    face_ratio = round((face_frames / analyzed) * 100.0, 1) if analyzed > 0 else 0.0
    minutes = max(duration_sec / 60.0, 1.0 / 60.0)
    blink_rate = round(blink_transitions / minutes, 1)

    avg_motion = float(np.mean(motion_deltas)) if motion_deltas else 0.0
    std_motion = float(np.std(motion_deltas)) if motion_deltas else 0.0
    motion_jitter = round(min(100.0, (std_motion * 6.5) + (avg_motion * 2.0)), 1)

    # Normal resting blink rate ~15-20/min; elevated >28/min or suppressed <6/min signals cognitive load
    blink_deviation = min(100.0, abs(blink_rate - 17.0) * 3.2) if face_frames > 0 else 25.0
    visual_stress = round(min(100.0, 0.6 * motion_jitter + 0.4 * blink_deviation), 1)

    return {
        "duration_sec": duration_sec,
        "fps": round(fps, 1),
        "frames_analyzed": analyzed,
        "face_detected_ratio": face_ratio,
        "blink_rate_per_min": blink_rate,
        "motion_jitter_index": motion_jitter,
        "visual_stress_index": visual_stress,
        "timeline": timeline[:120],
    }
