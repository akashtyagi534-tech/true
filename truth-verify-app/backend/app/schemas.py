from pydantic import BaseModel, Field


class GoogleLoginIn(BaseModel):
    credential: str = ""
    id_token: str = ""
    access_token: str = ""
    email: str = ""
    name: str = ""
    picture: str = ""
    google_sub: str = ""


class DevLoginIn(BaseModel):
    email: str
    name: str = ""
    password: str = ""


class CreateSessionIn(BaseModel):
    title: str = Field(default="", max_length=200)
    questions: list[str] = Field(default_factory=list)


class AddQuestionIn(BaseModel):
    question: str = Field(..., min_length=1, max_length=400)


class RechargeRequestIn(BaseModel):
    amount: float = Field(..., gt=0)
    utr: str = Field(..., min_length=4, max_length=100)


class AdminSettingsIn(BaseModel):
    price_per_question: int = Field(..., ge=0, le=10000)
    min_recharge: int = Field(..., ge=1, le=100000)
    free_questions: int = Field(..., ge=0, le=100)
    upi_id: str = Field(..., min_length=3, max_length=120)


class AdminWalletAdjustIn(BaseModel):
    delta: float


class OtaConfigIn(BaseModel):
    app_version: str | None = None
    maintenance_message: str | None = None
    consent_banner: str | None = None
    baseline_seconds: int | None = None
    baseline_questions: list[str] | None = None
    active_detectors: dict[str, bool] | None = None
    scoring_weights: dict[str, float] | None = None


class WindowIn(BaseModel):
    t: float
    phase: str = "answer"
    question_idx: int = -1
    frames: int = 0
    face_frames: int = 0
    bpm: float | None = None
    latency: float | None = None
    features: dict = Field(default_factory=dict)
    transcript: str = ""


class WindowBatchIn(BaseModel):
    windows: list[WindowIn]


class WindowOut(BaseModel):
    t: float
    question_idx: int
    score: float | None
    confidence: float | None
    top_signals: list[str]
    verdict_text: str = ""
    bpm: float | None = None
    latency: float | None = None
    transcript: str


class ContradictionOut(BaseModel):
    type: str
    message: str
    t_first: float
    t_second: float


class ReportOut(BaseModel):
    id: str
    title: str
    status: str
    created_at: str
    face_coverage: float
    confidence_label: str
    overall_score: float | None
    overall_verdict: str
    avg_bpm: float | None
    baseline_bpm: float | None
    questions: list[str]
    windows: list[WindowOut]
    spikes: list[float]
    contradictions: list[ContradictionOut]


class SessionSummaryOut(BaseModel):
    id: str
    title: str
    status: str
    created_at: str
    overall_score: float | None
    overall_verdict: str
    spikes_count: int
    face_coverage: float
