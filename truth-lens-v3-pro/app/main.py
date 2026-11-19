import uuid
from pathlib import Path

from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import desc
from sqlalchemy.orm import Session as DbSession

from . import moderation, nlp
from .auth import (
    get_admin_user,
    get_current_user,
    sign_token,
    upsert_user,
    verify_google_id_token,
)
from .config import settings
from .db import (
    FlaggedAlertRow,
    RechargeRow,
    SessionRow,
    UserRow,
    WindowRow,
    check_db_connection,
    get_app_config,
    get_db,
    init_db,
    set_app_config,
)
from .schemas import (
    AddQuestionIn,
    AdminSettingsIn,
    AdminWalletAdjustIn,
    CreateSessionIn,
    DevLoginIn,
    GoogleLoginIn,
    RechargeRequestIn,
    ReportOut,
    SessionSummaryOut,
    WindowBatchIn,
)
from .scoring import (
    build_baseline,
    confidence_label,
    overall_verdict_label,
    score_window,
)

BASE_DIR = Path(__file__).resolve().parent.parent
STATIC_DIR = BASE_DIR / "static"

app = FastAPI(title="Truth Lens Pro v3", version="3.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def _startup() -> None:
    init_db()


@app.get("/health")
def health() -> dict:
    db_ok = check_db_connection()
    return {
        "ok": db_ok,
        "status": "ok" if db_ok else "db_error",
        "database": settings.db_dialect,
        "db_connected": db_ok,
        "version": "3.0.0",
    }


@app.get("/api/public-config")
def public_config(db: DbSession = Depends(get_db)) -> dict:
    cfg = get_app_config(db)
    return {
        "google_client_id": settings.google_client_id,
        "demo_login_enabled": not bool(settings.google_client_id),
        **cfg,
    }


@app.post("/api/auth/google")
async def auth_google(payload: GoogleLoginIn, db: DbSession = Depends(get_db)) -> dict:
    info = await verify_google_id_token(payload.credential)
    user = upsert_user(
        db,
        email=info["email"],
        name=info.get("name", ""),
        picture=info.get("picture", ""),
        google_sub=info.get("sub"),
    )
    if user.is_banned:
        raise HTTPException(status_code=403, detail="Account suspended by Admin")
    token = sign_token({"uid": user.id, "email": user.email, "admin": user.is_admin})
    return {"token": token, "user": _user_dict(user, get_app_config(db))}


@app.post("/api/auth/dev-login")
def auth_dev(payload: DevLoginIn, db: DbSession = Depends(get_db)) -> dict:
    email_low = payload.email.strip().lower()
    if not email_low or "@" not in email_low:
        raise HTTPException(status_code=400, detail="Valid email required")

    if settings.google_client_id:
        if email_low not in settings.admin_email_set or payload.password != settings.admin_password:
            raise HTTPException(status_code=403, detail="Use Google Sign-In")

    user = upsert_user(db, email=email_low, name=payload.name or email_low.split("@")[0])
    if payload.password and payload.password == settings.admin_password and email_low in settings.admin_email_set:
        user.is_admin = True
        db.commit()
    token = sign_token({"uid": user.id, "email": user.email, "admin": user.is_admin})
    return {"token": token, "user": _user_dict(user, get_app_config(db))}


def _user_dict(user: UserRow, cfg: dict) -> dict:
    free_left = max(0, cfg["free_questions"] - user.free_questions_used)
    return {
        "id": user.id,
        "email": user.email,
        "name": user.name,
        "picture": user.picture,
        "wallet_balance": round(user.wallet_balance, 2),
        "free_questions_left": free_left,
        "total_questions_asked": user.total_questions_asked,
        "is_admin": user.is_admin,
    }


@app.get("/api/me")
def me(user: UserRow = Depends(get_current_user), db: DbSession = Depends(get_db)) -> dict:
    cfg = get_app_config(db)
    recharges = (
        db.query(RechargeRow)
        .filter(RechargeRow.user_id == user.id)
        .order_by(desc(RechargeRow.created_at))
        .limit(10)
        .all()
    )
    return {
        "user": _user_dict(user, cfg),
        "pricing": cfg,
        "recharges": [
            {
                "id": r.id,
                "amount": r.amount,
                "utr": r.utr,
                "status": r.status,
                "created_at": r.created_at.isoformat(),
            }
            for r in recharges
        ],
    }


def _charge_for_questions(db: DbSession, user: UserRow, count: int) -> dict:
    if count <= 0:
        return {"free_used": 0, "paid_used": 0, "amount_charged": 0}
    cfg = get_app_config(db)
    price = cfg["price_per_question"]
    free_left = max(0, cfg["free_questions"] - user.free_questions_used)
    free_to_use = min(free_left, count)
    paid_count = count - free_to_use
    cost = paid_count * price

    if cost > user.wallet_balance:
        raise HTTPException(
            status_code=402,
            detail=f"Balance kam hai! {paid_count} paid sawaal ke liye ₹{cost} chahiye (Wallet: ₹{user.wallet_balance:.0f}). Kam se kam ₹{cfg['min_recharge']} ka recharge karein.",
        )

    user.free_questions_used += free_to_use
    user.wallet_balance = round(user.wallet_balance - cost, 2)
    user.total_questions_asked += count
    return {"free_used": free_to_use, "paid_used": paid_count, "amount_charged": cost}


@app.post("/api/wallet/recharge")
def request_recharge(
    payload: RechargeRequestIn,
    user: UserRow = Depends(get_current_user),
    db: DbSession = Depends(get_db),
) -> dict:
    cfg = get_app_config(db)
    if payload.amount < cfg["min_recharge"]:
        raise HTTPException(
            status_code=400,
            detail=f"Minimum recharge ₹{cfg['min_recharge']} ka hona chahiye.",
        )
    row = RechargeRow(
        id=uuid.uuid4().hex[:12],
        user_id=user.id,
        amount=round(payload.amount, 2),
        utr=payload.utr.strip(),
        status="pending",
    )
    db.add(row)
    db.commit()
    return {"id": row.id, "status": "pending", "message": "Recharge request bhej di gayi hai. Admin verify karte hi wallet update ho jayega."}


@app.post("/api/moderation/flag")
async def flag_unsafe_clip(
    session_id: str = Form(default=""),
    question_text: str = Form(default=""),
    matched_keywords: str = Form(default=""),
    video: UploadFile | None = File(default=None),
    user: UserRow = Depends(get_current_user),
    db: DbSession = Depends(get_db),
) -> dict:
    alert_id = uuid.uuid4().hex[:12]
    filename = ""
    if video is not None:
        ext = ".webm"
        filename = f"alert_{alert_id}{ext}"
        dest = settings.flagged_video_dir / filename
        data = await video.read()
        if len(data) <= 15 * 1024 * 1024:
            dest.write_bytes(data)
        else:
            filename = ""

    kw_list = [k.strip() for k in matched_keywords.split(",") if k.strip()]
    if not kw_list:
        kw_list = moderation.check_unsafe(question_text)

    row = FlaggedAlertRow(
        id=alert_id,
        user_id=user.id,
        user_email=user.email,
        session_id=session_id,
        question_text=question_text[:1000],
        matched_keywords=kw_list,
        video_filename=filename,
    )
    db.add(row)
    db.commit()
    return {"ok": True, "alert_id": alert_id}


def _get_session(db: DbSession, session_id: str) -> SessionRow:
    row = db.get(SessionRow, session_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Session not found")
    return row


@app.get("/api/sessions", response_model=list[SessionSummaryOut])
def list_sessions(
    user: UserRow = Depends(get_current_user), db: DbSession = Depends(get_db)
) -> list[SessionSummaryOut]:
    q = db.query(SessionRow)
    if not user.is_admin:
        q = q.filter(SessionRow.user_id == user.id)
    rows = q.order_by(desc(SessionRow.created_at)).limit(50).all()
    out = []
    for row in rows:
        scored = [w for w in row.windows if w.score is not None]
        overall = round(sum(w.score for w in scored) / len(scored), 1) if scored else None
        spikes = sum(1 for w in scored if w.score is not None and w.score >= 62)
        out.append(
            SessionSummaryOut(
                id=row.id,
                title=row.title,
                status=row.status,
                created_at=row.created_at.isoformat(),
                overall_score=overall,
                overall_verdict=overall_verdict_label(overall, spikes),
                spikes_count=spikes,
                face_coverage=round(row.face_coverage, 3),
            )
        )
    return out


@app.post("/api/sessions")
def create_session(
    payload: CreateSessionIn,
    user: UserRow = Depends(get_current_user),
    db: DbSession = Depends(get_db),
) -> dict:
    clean_qs = [q.strip() for q in payload.questions if q.strip()]
    bill_count = max(1, len(clean_qs))
    billing = _charge_for_questions(db, user, bill_count)

    unsafe_hits = []
    for q in clean_qs:
        hits = moderation.check_unsafe(q)
        if hits:
            unsafe_hits.append({"question": q, "keywords": hits})

    session_id = uuid.uuid4().hex[:16]
    row = SessionRow(
        id=session_id,
        user_id=user.id,
        title=payload.title.strip() or "Untitled session",
        questions=clean_qs,
        status="baseline",
    )
    db.add(row)
    db.commit()
    return {
        "id": session_id,
        "baseline_seconds": settings.baseline_seconds,
        "window_seconds": settings.window_seconds,
        "questions": row.questions,
        "billing": billing,
        "user": _user_dict(user, get_app_config(db)),
        "unsafe_hits": unsafe_hits,
    }


@app.post("/api/sessions/{session_id}/questions")
def add_question(
    session_id: str,
    payload: AddQuestionIn,
    user: UserRow = Depends(get_current_user),
    db: DbSession = Depends(get_db),
) -> dict:
    row = _get_session(db, session_id)
    billing = _charge_for_questions(db, user, 1)
    q_text = payload.question.strip()
    unsafe_kw = moderation.check_unsafe(q_text)

    qs = list(row.questions or [])
    qs.append(q_text)
    row.questions = qs
    db.commit()
    return {
        "questions": row.questions,
        "index": len(qs) - 1,
        "billing": billing,
        "user": _user_dict(user, get_app_config(db)),
        "unsafe_keywords": unsafe_kw,
    }


@app.delete("/api/sessions/{session_id}")
def delete_session(
    session_id: str,
    user: UserRow = Depends(get_current_user),
    db: DbSession = Depends(get_db),
) -> dict:
    row = _get_session(db, session_id)
    if not user.is_admin and row.user_id != user.id:
        raise HTTPException(status_code=403, detail="Not allowed")
    db.delete(row)
    db.commit()
    return {"deleted": session_id}


@app.post("/api/sessions/{session_id}/windows")
def push_windows(
    session_id: str,
    payload: WindowBatchIn,
    user: UserRow = Depends(get_current_user),
    db: DbSession = Depends(get_db),
) -> dict:
    row = _get_session(db, session_id)
    if row.status == "finished":
        raise HTTPException(status_code=409, detail="Session already finished")

    baseline_samples = [w.features for w in row.windows if w.phase == "baseline"]
    frames_total = row.frames_total + sum(w.frames for w in payload.windows)
    face_frames = int(row.face_coverage * row.frames_total) + sum(
        w.face_frames for w in payload.windows
    )
    coverage = (face_frames / frames_total) if frames_total else 0.0

    baseline_ready = len(baseline_samples) >= 3 and (
        (row.windows[-1].t if row.windows else 0.0) >= settings.baseline_seconds
        or any(w.phase != "baseline" for w in payload.windows)
    )
    if baseline_ready and row.status == "baseline":
        row.baseline = build_baseline(baseline_samples)
        row.status = "answer"

    baseline_bpm = None
    if row.baseline and "bpm" in row.baseline:
        baseline_bpm = row.baseline["bpm"][0]

    results = []
    for item in payload.windows:
        enriched = dict(item.features)
        window_seconds = max(0.5, settings.window_seconds)
        enriched.update(
            nlp.enrich(
                item.transcript,
                window_seconds,
                float(item.features.get("pause_ratio", 0.0)),
            )
        )
        if item.bpm is not None and item.bpm > 40:
            enriched["bpm"] = float(item.bpm)
            if baseline_bpm is not None:
                enriched["bpm_delta"] = round(float(item.bpm) - baseline_bpm, 2)
        if item.latency is not None and item.latency >= 0:
            enriched["response_latency"] = float(item.latency)

        unsafe_kw = moderation.check_unsafe(item.transcript)

        score = confidence = None
        signals: list[str] = []
        verdict_text = ""
        followup = None
        radar: dict[str, int] = {}

        if row.status == "answer" and item.phase == "answer" and row.baseline:
            score, confidence, signals, verdict_text, followup, radar = score_window(
                enriched, row.baseline, coverage, len(row.windows)
            )

        db.add(
            WindowRow(
                session_id=session_id,
                t=item.t,
                phase=item.phase,
                question_idx=item.question_idx,
                features=enriched,
                score=score,
                confidence=confidence,
                top_signals=signals,
                verdict_text=verdict_text,
                bpm=item.bpm,
                latency=item.latency,
                transcript=item.transcript,
            )
        )
        results.append(
            {
                "t": item.t,
                "score": score,
                "confidence": confidence,
                "top_signals": signals,
                "verdict_text": verdict_text,
                "cross_question": followup,
                "radar": radar,
                "unsafe_keywords": unsafe_kw,
            }
        )

    row.frames_total = frames_total
    row.face_coverage = coverage
    db.commit()
    return {"status": row.status, "coverage": round(coverage, 3), "windows": results}


@app.post("/api/sessions/{session_id}/finish")
def finish_session(
    session_id: str,
    user: UserRow = Depends(get_current_user),
    db: DbSession = Depends(get_db),
) -> dict:
    row = _get_session(db, session_id)
    row.status = "finished"
    db.commit()
    return {"id": row.id, "report_url": f"/report/{row.id}"}


@app.get("/api/sessions/{session_id}", response_model=ReportOut)
def get_report(session_id: str, db: DbSession = Depends(get_db)) -> ReportOut:
    row = _get_session(db, session_id)
    scored = [w for w in row.windows if w.score is not None]
    overall = round(sum(w.score for w in scored) / len(scored), 1) if scored else None
    peak_conf = max((w.confidence or 0) for w in scored) if scored else None
    spikes = [round(w.t, 2) for w in scored if w.score is not None and w.score >= 62]
    bpms = [w.bpm for w in row.windows if w.bpm is not None and w.bpm > 40]
    avg_bpm = round(sum(bpms) / len(bpms), 1) if bpms else None
    baseline_bpm = (
        round(row.baseline["bpm"][0], 1)
        if row.baseline and "bpm" in row.baseline
        else None
    )
    answer_windows = [w for w in row.windows if w.phase == "answer"]
    contradictions = nlp.detect_contradictions(answer_windows)

    windows_out = [
        {
            "t": round(w.t, 2),
            "question_idx": w.question_idx,
            "score": w.score,
            "confidence": w.confidence,
            "top_signals": w.top_signals or [],
            "verdict_text": w.verdict_text or "",
            "bpm": round(w.bpm, 1) if w.bpm is not None else None,
            "latency": round(w.latency, 2) if w.latency is not None else None,
            "transcript": w.transcript,
        }
        for w in answer_windows
    ]

    return ReportOut(
        id=row.id,
        title=row.title,
        status=row.status,
        created_at=row.created_at.isoformat(),
        face_coverage=round(row.face_coverage, 3),
        confidence_label=confidence_label(peak_conf, row.face_coverage),
        overall_score=overall,
        overall_verdict=overall_verdict_label(overall, len(spikes)),
        avg_bpm=avg_bpm,
        baseline_bpm=baseline_bpm,
        questions=row.questions,
        windows=windows_out,
        spikes=spikes,
        contradictions=contradictions,
    )


@app.get("/api/admin/overview")
def admin_overview(admin: UserRow = Depends(get_admin_user), db: DbSession = Depends(get_db)) -> dict:
    cfg = get_app_config(db)
    users = db.query(UserRow).order_by(desc(UserRow.created_at)).limit(100).all()
    recharges = db.query(RechargeRow).order_by(desc(RechargeRow.created_at)).limit(100).all()
    alerts = db.query(FlaggedAlertRow).order_by(desc(FlaggedAlertRow.created_at)).limit(100).all()

    user_map = {u.id: u.email for u in users}
    total_revenue = sum(r.amount for r in recharges if r.status == "approved")
    total_questions = sum(u.total_questions_asked for u in users)

    return {
        "settings": cfg,
        "stats": {
            "total_users": len(users),
            "total_revenue": round(total_revenue, 2),
            "total_questions": total_questions,
            "pending_recharges": sum(1 for r in recharges if r.status == "pending"),
            "flagged_alerts": len(alerts),
        },
        "users": [
            {
                "id": u.id,
                "email": u.email,
                "name": u.name,
                "wallet_balance": round(u.wallet_balance, 2),
                "free_questions_used": u.free_questions_used,
                "total_questions_asked": u.total_questions_asked,
                "is_admin": u.is_admin,
                "is_banned": u.is_banned,
            }
            for u in users
        ],
        "recharges": [
            {
                "id": r.id,
                "user_id": r.user_id,
                "user_email": user_map.get(r.user_id, r.user_id),
                "amount": r.amount,
                "utr": r.utr,
                "status": r.status,
                "created_at": r.created_at.isoformat(),
            }
            for r in recharges
        ],
        "alerts": [
            {
                "id": a.id,
                "user_email": a.user_email,
                "session_id": a.session_id,
                "question_text": a.question_text,
                "matched_keywords": a.matched_keywords or [],
                "video_url": f"/api/admin/videos/{a.video_filename}" if a.video_filename else "",
                "reviewed": a.reviewed,
                "created_at": a.created_at.isoformat(),
            }
            for a in alerts
        ],
    }


@app.post("/api/admin/settings")
def admin_update_settings(
    payload: AdminSettingsIn,
    admin: UserRow = Depends(get_admin_user),
    db: DbSession = Depends(get_db),
) -> dict:
    set_app_config(db, "price_per_question", str(payload.price_per_question))
    set_app_config(db, "min_recharge", str(payload.min_recharge))
    set_app_config(db, "free_questions", str(payload.free_questions))
    set_app_config(db, "upi_id", payload.upi_id.strip())
    db.commit()
    return {"ok": True, "settings": get_app_config(db)}


@app.post("/api/admin/recharges/{recharge_id}/{action}")
def admin_handle_recharge(
    recharge_id: str,
    action: str,
    admin: UserRow = Depends(get_admin_user),
    db: DbSession = Depends(get_db),
) -> dict:
    row = db.get(RechargeRow, recharge_id)
    if not row:
        raise HTTPException(status_code=404, detail="Recharge not found")
    if row.status != "pending":
        raise HTTPException(status_code=409, detail="Already processed")
    if action == "approve":
        row.status = "approved"
        u = db.get(UserRow, row.user_id)
        if u:
            u.wallet_balance = round(u.wallet_balance + row.amount, 2)
    elif action == "reject":
        row.status = "rejected"
    else:
        raise HTTPException(status_code=400, detail="Invalid action")
    db.commit()
    return {"ok": True, "status": row.status}


@app.post("/api/admin/users/{user_id}/wallet")
def admin_adjust_wallet(
    user_id: str,
    payload: AdminWalletAdjustIn,
    admin: UserRow = Depends(get_admin_user),
    db: DbSession = Depends(get_db),
) -> dict:
    u = db.get(UserRow, user_id)
    if not u:
        raise HTTPException(status_code=404, detail="User not found")
    u.wallet_balance = max(0.0, round(u.wallet_balance + payload.delta, 2))
    db.commit()
    return {"ok": True, "wallet_balance": u.wallet_balance}


@app.post("/api/admin/users/{user_id}/toggle-ban")
def admin_toggle_ban(
    user_id: str,
    admin: UserRow = Depends(get_admin_user),
    db: DbSession = Depends(get_db),
) -> dict:
    u = db.get(UserRow, user_id)
    if not u:
        raise HTTPException(status_code=404, detail="User not found")
    u.is_banned = not u.is_banned
    db.commit()
    return {"ok": True, "is_banned": u.is_banned}


@app.get("/api/admin/videos/{filename}")
def admin_get_video(filename: str) -> FileResponse:
    safe_name = Path(filename).name
    path = settings.flagged_video_dir / safe_name
    if not path.exists():
        raise HTTPException(status_code=404, detail="Video not found")
    return FileResponse(path, media_type="video/webm")


@app.get("/admin")
def admin_page() -> FileResponse:
    return FileResponse(STATIC_DIR / "admin.html")


@app.get("/report/{session_id}")
def report_page(session_id: str) -> FileResponse:
    return FileResponse(STATIC_DIR / "report.html")


@app.get("/history")
def history_page() -> FileResponse:
    return FileResponse(STATIC_DIR / "history.html")


@app.get("/")
def index() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
