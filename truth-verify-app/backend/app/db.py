import json
from datetime import datetime, timezone

from sqlalchemy import (
    Boolean,
    JSON,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    create_engine,
    inspect,
    text,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship, sessionmaker

from .config import settings

_db_url = settings.normalised_db_url
_is_sqlite = _db_url.startswith("sqlite")

engine = create_engine(
    _db_url,
    pool_pre_ping=True,
    **({} if _is_sqlite else {"pool_recycle": 300}),
    connect_args={"check_same_thread": False} if _is_sqlite else {},
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Base(DeclarativeBase):
    pass


class AppSetting(Base):
    __tablename__ = "app_settings"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[str] = mapped_column(Text)


class UserRow(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    google_sub: Mapped[str | None] = mapped_column(String(128), unique=True, nullable=True)
    email: Mapped[str] = mapped_column(String(191), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(200), default="")
    picture: Mapped[str] = mapped_column(String(500), default="")
    wallet_balance: Mapped[float] = mapped_column(Float, default=0.0)
    free_questions_used: Mapped[int] = mapped_column(Integer, default=0)
    total_questions_asked: Mapped[int] = mapped_column(Integer, default=0)
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    is_banned: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class RechargeRow(Base):
    __tablename__ = "recharges"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    amount: Mapped[float] = mapped_column(Float)
    utr: Mapped[str] = mapped_column(String(100), default="")
    status: Mapped[str] = mapped_column(String(20), default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class FlaggedAlertRow(Base):
    __tablename__ = "flagged_alerts"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    user_id: Mapped[str | None] = mapped_column(String(32), nullable=True)
    user_email: Mapped[str] = mapped_column(String(200), default="anonymous")
    session_id: Mapped[str] = mapped_column(String(32), default="")
    question_text: Mapped[str] = mapped_column(Text, default="")
    matched_keywords: Mapped[list] = mapped_column(JSON, default=list)
    video_filename: Mapped[str] = mapped_column(String(255), default="")
    reviewed: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class SessionRow(Base):
    __tablename__ = "sessions"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)
    user_id: Mapped[str | None] = mapped_column(String(32), nullable=True, index=True)
    title: Mapped[str] = mapped_column(String(200), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    status: Mapped[str] = mapped_column(String(20), default="baseline")
    baseline: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    face_coverage: Mapped[float] = mapped_column(Float, default=0.0)
    frames_total: Mapped[int] = mapped_column(Integer, default=0)
    questions: Mapped[list] = mapped_column(JSON, default=list)

    windows: Mapped[list["WindowRow"]] = relationship(
        back_populates="session", cascade="all, delete-orphan", order_by="WindowRow.t"
    )


class WindowRow(Base):
    __tablename__ = "windows"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    session_id: Mapped[str] = mapped_column(
        ForeignKey("sessions.id", ondelete="CASCADE"), index=True
    )
    t: Mapped[float] = mapped_column(Float)
    phase: Mapped[str] = mapped_column(String(20), default="answer")
    question_idx: Mapped[int] = mapped_column(Integer, default=-1)
    features: Mapped[dict] = mapped_column(JSON)
    score: Mapped[float | None] = mapped_column(Float, nullable=True)
    confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    top_signals: Mapped[list] = mapped_column(JSON, default=list)
    verdict_text: Mapped[str] = mapped_column(Text, default="")
    bpm: Mapped[float | None] = mapped_column(Float, nullable=True)
    latency: Mapped[float | None] = mapped_column(Float, nullable=True)
    transcript: Mapped[str] = mapped_column(Text, default="")

    session: Mapped[SessionRow] = relationship(back_populates="windows")


def get_app_config(db) -> dict:
    defaults = {
        "price_per_question": str(settings.default_price_per_question),
        "min_recharge": str(settings.default_min_recharge),
        "free_questions": str(settings.default_free_questions),
        "upi_id": settings.default_upi_id,
    }
    rows = db.query(AppSetting).all()
    for r in rows:
        defaults[r.key] = r.value
    return {
        "price_per_question": max(0, int(float(defaults["price_per_question"]))),
        "min_recharge": max(1, int(float(defaults["min_recharge"]))),
        "free_questions": max(0, int(float(defaults["free_questions"]))),
        "upi_id": defaults["upi_id"],
    }


def set_app_config(db, key: str, value: str) -> None:
    row = db.get(AppSetting, key)
    if row is None:
        db.add(AppSetting(key=key, value=str(value)))
    else:
        row.value = str(value)


DEFAULT_OTA_BASELINE_QUESTIONS = [
    "Aapka poora naam kya hai aur aaj kaunsi tareekh hai?",
    "Aaj subah aapne nashte mein kya khaya tha?",
    "Aap abhi kis shehar aur kamre mein baithe hain?",
]

DEFAULT_ACTIVE_DETECTORS = {
    "ocular_micro_expressions": True,
    "rppg_heart_rate": True,
    "kinesic_pose_hands": True,
    "bio_acoustic_tremor": True,
    "deepfake_liveness": True,
    "voice_clone_check": True,
    "ai_interrogation_coach": True,
    "hindi_voice_tts": True,
}

DEFAULT_SCORING_WEIGHTS = {
    "visual": 0.45,
    "acoustic": 0.45,
    "cognitive": 0.10,
}


def get_ota_config(db) -> dict:
    pricing = get_app_config(db)
    raw_map = {r.key: r.value for r in db.query(AppSetting).all()}

    def _parse_json(key: str, fallback):
        raw = raw_map.get(key)
        if not raw:
            return fallback
        try:
            parsed = json.loads(raw)
            return parsed if isinstance(parsed, type(fallback)) else fallback
        except Exception:
            return fallback

    return {
        "app_version": raw_map.get("ota_app_version") or settings.app_version,
        "maintenance_message": raw_map.get("ota_maintenance_message", settings.maintenance_message),
        "consent_banner": raw_map.get(
            "ota_consent_banner",
            "CONSENT-BASED SCANNER: Visible camera & mic active. Non-legal behavioral stress analysis.",
        ),
        "baseline_seconds": int(float(raw_map.get("ota_baseline_seconds", settings.baseline_seconds))),
        "baseline_questions": _parse_json("ota_baseline_questions", DEFAULT_OTA_BASELINE_QUESTIONS),
        "active_detectors": {
            **DEFAULT_ACTIVE_DETECTORS,
            **_parse_json("ota_active_detectors", {}),
        },
        "scoring_weights": {
            **DEFAULT_SCORING_WEIGHTS,
            **_parse_json("ota_scoring_weights", {}),
        },
        "pricing": pricing,
        "google_client_id": settings.google_client_id,
    }


def set_ota_config(db, data: dict) -> dict:
    if "app_version" in data and data["app_version"] is not None:
        set_app_config(db, "ota_app_version", str(data["app_version"]).strip() or settings.app_version)
    if "maintenance_message" in data and data["maintenance_message"] is not None:
        set_app_config(db, "ota_maintenance_message", str(data["maintenance_message"]).strip())
    if "consent_banner" in data and data["consent_banner"] is not None:
        set_app_config(db, "ota_consent_banner", str(data["consent_banner"]).strip())
    if "baseline_seconds" in data and data["baseline_seconds"] is not None:
        set_app_config(db, "ota_baseline_seconds", str(max(5, min(20, int(data["baseline_seconds"])))))
    if "baseline_questions" in data and isinstance(data["baseline_questions"], list):
        clean_qs = [str(q).strip() for q in data["baseline_questions"] if str(q).strip()]
        if clean_qs:
            set_app_config(db, "ota_baseline_questions", json.dumps(clean_qs[:6]))
    if "active_detectors" in data and isinstance(data["active_detectors"], dict):
        set_app_config(db, "ota_active_detectors", json.dumps(data["active_detectors"]))
    if "scoring_weights" in data and isinstance(data["scoring_weights"], dict):
        set_app_config(db, "ota_scoring_weights", json.dumps(data["scoring_weights"]))
    db.commit()
    return get_ota_config(db)


def init_db() -> None:
    Base.metadata.create_all(bind=engine)
    inspector = inspect(engine)
    migrations = [
        ("sessions", "user_id", "ALTER TABLE sessions ADD COLUMN user_id VARCHAR(32)"),
        ("windows", "top_signals", "ALTER TABLE windows ADD COLUMN top_signals JSON"),
        ("windows", "verdict_text", "ALTER TABLE windows ADD COLUMN verdict_text TEXT"),
        ("windows", "bpm", "ALTER TABLE windows ADD COLUMN bpm FLOAT"),
        ("windows", "latency", "ALTER TABLE windows ADD COLUMN latency FLOAT"),
    ]
    existing_cols: dict[str, set[str]] = {}
    for table_name, col_name, stmt in migrations:
        if table_name not in existing_cols:
            try:
                existing_cols[table_name] = {c["name"] for c in inspector.get_columns(table_name)}
            except Exception:
                existing_cols[table_name] = set()
        if col_name in existing_cols[table_name]:
            continue
        try:
            with engine.begin() as conn:
                conn.execute(text(stmt))
            existing_cols[table_name].add(col_name)
        except Exception:
            pass


def check_db_connection() -> bool:
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return True
    except Exception:
        return False


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
