from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./data/app.db"
    data_dir: str = "./data"
    baseline_seconds: float = 25.0
    window_seconds: float = 2.0
    min_windows_for_score: int = 4
    allowed_origins: str = "*"

    jwt_secret: str = "truth-lens-dev-secret-change-in-prod"
    google_client_id: str = ""
    admin_emails: str = "akashtyagi534@gmail.com"
    admin_password: str = "admin123"

    default_price_per_question: int = 10
    default_min_recharge: int = 50
    default_free_questions: int = 3
    default_upi_id: str = "yourupi@oksbi"

    @property
    def origins(self) -> list[str]:
        if self.allowed_origins.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.allowed_origins.split(",") if o.strip()]

    @property
    def admin_email_set(self) -> set[str]:
        return {e.strip().lower() for e in self.admin_emails.split(",") if e.strip()}

    @property
    def normalised_db_url(self) -> str:
        url = self.database_url
        if url.startswith("postgres://"):
            url = url.replace("postgres://", "postgresql+psycopg://", 1)
        elif url.startswith("postgresql://"):
            url = url.replace("postgresql://", "postgresql+psycopg://", 1)
        return url

    @property
    def flagged_video_dir(self) -> Path:
        p = Path(self.data_dir) / "flagged_videos"
        p.mkdir(parents=True, exist_ok=True)
        return p


settings = Settings()

if settings.normalised_db_url.startswith("sqlite"):
    raw = settings.normalised_db_url.replace("sqlite:///", "", 1)
    if raw and raw != ":memory:":
        Path(raw).parent.mkdir(parents=True, exist_ok=True)
