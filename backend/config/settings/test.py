from .base import *

DEBUG = False

# Fast password hasher for tests
PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.MD5PasswordHasher",
]

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": ":memory:",
    }
}

REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"] = {
    "anon": "10000/minute",
    "user": "10000/minute",
    "login": "10000/minute",
}
