.PHONY: install test lint api up down logs

install:
	python -m pip install -e ".[dev]"

test:
	pytest -q

lint:
	ruff check app tests

api:
	uvicorn app.main:app --reload

up:
	docker compose up --build

down:
	docker compose down

logs:
	docker compose logs -f
