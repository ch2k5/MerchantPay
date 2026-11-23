.PHONY: up down seed test test-cov run-backend run-web lint format clean

VENV ?= ./venv/bin

up:
	docker compose up --build -d

down:
	docker compose down

seed:
	cd backend && ../$(VENV)/python manage.py seed_demo --seed 42

test:
	cd backend && ../$(VENV)/pytest tests/ -v

test-cov:
	cd backend && ../$(VENV)/pytest tests/ -v --cov=apps --cov-report=term-missing

run-backend:
	cd backend && ../$(VENV)/python manage.py runserver 0.0.0.0:8000

run-web:
	cd mobile && flutter run -d chrome --web-port 8080

lint:
	cd backend && ../$(VENV)/ruff check .
	cd mobile && flutter analyze

format:
	cd backend && ../$(VENV)/ruff format . && ../$(VENV)/black .
	cd mobile && dart format .

clean:
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
	rm -rf backend/.pytest_cache backend/htmlcov backend/.coverage
