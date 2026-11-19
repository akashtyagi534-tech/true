import os
from pathlib import Path
from urllib.parse import quote_plus
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
        raw = (self.database_url or "").strip()
        if not raw or raw == "sqlite:///./data/app.db":
            for env_key in (
                "DATABASE_URL",
                "DATABASE_PRIVATE_URL",
                "POSTGRES_URL",
                "MYSQL_URL",
                "MYSQL_PRIVATE_URL",
            ):
                val = os.getenv(env_key, "").strip()
                if val:
                    raw = val
                    break
            else:
                if os.getenv("PGHOST") and os.getenv("PGDATABASE"):
                    pg_user = quote_plus(os.getenv("PGUSER", "postgres"))
                    pg_pass = quote_plus(os.getenv("PGPASSWORD", ""))
                    pg_host = os.getenv("PGHOST", "localhost")
                    pg_port = os.getenv("PGPORT", "5432")
                    pg_db = os.getenv("PGDATABASE", "railway")
                    raw = f"postgresql://{pg_user}:{pg_pass}@{pg_host}:{pg_port}/{pg_db}"
                elif os.getenv("MYSQLHOST") and os.getenv("MYSQLDATABASE"):
                    my_user = quote_plus(os.getenv("MYSQLUSER", "root"))
                    my_pass = quote_plus(os.getenv("MYSQLPASSWORD", ""))
                    my_host = os.getenv("MYSQLHOST", "localhost")
                    my_port = os.getenv("MYSQLPORT", "3306")
                    my_db = os.getenv("MYSQLDATABASE", "railway")
                    raw = f"mysql://{my_user}:{my_pass}@{my_host}:{my_port}/{my_db}"

        if raw.startswith("postgres://"):
            return raw.replace("postgres://", "postgresql+psycopg://", 1)
        if raw.startswith("postgresql://"):
            return raw.replace("postgresql://", "postgresql+psycopg://", 1)
        if raw.startswith("mysql://"):
            return raw.replace("mysql://", "mysql+pymysql://", 1)
        return raw or "sqlite:///./data/app.db"

    @property
    def db_dialect(self) -> str:
        url = self.normalised_db_url
        if url.startswith("postgresql"):
            return "postgresql"
        if url.startswith("mysql"):
            return "mysql"
        return "sqlite"

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
