# PhotoShare Backend

This is the backend server for the PhotoShare application built with FastAPI and Poetry.

## Prerequisites

- Python 3.9 or higher
- Poetry (Python package manager)

## Setup

1. Install Poetry (if not already installed):
   ```bash
   curl -sSL https://install.python-poetry.org | python3 -
   ```

2. Install dependencies:
   ```bash
   poetry install
   ```

3. Copy the `.env.example` file to `.env` and update the values:
   ```bash
   cp .env.example .env
   ```

## Running the Server

1. Activate the virtual environment:
   ```bash
   poetry shell
   ```

2. Run the server:
   ```bash
   uvicorn app.main:app --host localhost --port 8000 --reload
   ```

The API will be available at `http://localhost:8000`
API documentation (Swagger UI) will be available at `http://localhost:8000/docs`

## Project Structure

```
backend/
├── app/
│   ├── api/        # API endpoints
│   ├── core/       # Core functionality, config
│   ├── models/     # Database models
│   ├── schemas/    # Pydantic models
│   ├── services/   # Business logic
│   └── main.py     # FastAPI application
├── tests/          # Test files
├── .env           # Environment variables
├── .gitignore     # Git ignore rules
└── pyproject.toml # Poetry dependencies
```

## Development

- Run tests: `pytest`
- Format code: `black .`
- Lint code: `flake8`