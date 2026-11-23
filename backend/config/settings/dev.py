import os

from .base import *

DEBUG = True

ALLOWED_HOSTS = ["*"]

# Database configuration: Use Postgres if DATABASE_URL or POSTGRES_DB is provided, otherwise SQLite for local dev
db_name = os.getenv("POSTGRES_DB")
if db_name:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": db_name,
            "USER": os.getenv("POSTGRES_USER", "merchant_user"),
            "PASSWORD": os.getenv("POSTGRES_PASSWORD", "merchant_secret_2026"),
            "HOST": os.getenv("POSTGRES_HOST", "127.0.0.1"),
            "PORT": os.getenv("POSTGRES_PORT", "5432"),
        }
    }
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "db.sqlite3",
        }
    }
