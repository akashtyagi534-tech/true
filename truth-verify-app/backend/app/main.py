import os
import subprocess
import tempfile
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from app.audio_analysis import analyze_audio
from app.scoring import compute_truth_score
from app.video_analysis import analyze_video

app = FastAPI(
    title="TruthVerify API",
    description="Multimodal video & audio stress and behavioral signal analysis API.",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health_check():
    return {"status": "ok", "service": "truth-verify-backend"}


@app.post("/analyze")
async def analyze_recording(file: UploadFile = File(...)):
    if not file.filename:
        raise HTTPException(status_code=400, detail="Missing uploaded media filename.")

    suffix = os.path.splitext(file.filename)[1] or ".mp4"
    with tempfile.TemporaryDirectory() as tmpdir:
        video_path = os.path.join(tmpdir, f"input{suffix}")
        audio_path = os.path.join(tmpdir, "extracted.wav")

        content = await file.read()
        if not content:
            raise HTTPException(status_code=400, detail="Uploaded file is empty.")

        with open(video_path, "wb") as f:
            f.write(content)

        # Extract mono 16kHz PCM audio via ffmpeg
        ffmpeg_cmd = [
            "ffmpeg",
            "-y",
            "-i",
            video_path,
            "-vn",
            "-acodec",
            "pcm_s16le",
            "-ar",
            "16000",
            "-ac",
            "1",
            audio_path,
        ]
        proc = subprocess.run(ffmpeg_cmd, capture_output=True, text=True)
        has_audio = proc.returncode == 0 and os.path.exists(audio_path) and os.path.getsize(audio_path) > 1024

        video_metrics = analyze_video(video_path)
        audio_metrics = (
            analyze_audio(audio_path)
            if has_audio
            else {
                "duration_sec": video_metrics["duration_sec"],
                "pitch_mean_hz": 0.0,
                "pitch_std_hz": 0.0,
                "energy_rms_mean": 0.0,
                "energy_spike_rate": 0.0,
                "pause_ratio": 0.0,
                "vocal_stress_index": 0.0,
                "audio_available": False,
                "timeline": [],
            }
        )

        report = compute_truth_score(video_metrics, audio_metrics)
        return report
