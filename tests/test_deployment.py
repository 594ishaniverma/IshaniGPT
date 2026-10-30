import os
from pathlib import Path

from app import validate_environment


def test_deployment_environment_example_has_persistence_paths():
    env = Path(".env.example").read_text(encoding="utf-8")
    for key in ("SQLITE_DATABASE_PATH", "CHECKPOINT_SQLITE_PATH", "CHROMA_PERSIST_DIRECTORY", "UPLOAD_DIR"):
        assert f"{key}=" in env


def test_docker_compose_defines_persistent_volumes_and_postgres():
    compose = Path("docker-compose.yml").read_text(encoding="utf-8")
    assert "postgres:" in compose
    assert "chatbot-checkpoints:" in compose
    assert "chatbot-chroma:" in compose
    assert "chatbot-uploads:" in compose


def test_production_environment_requires_deployment_settings(monkeypatch):
    for key in ("GOOGLE_API_KEY", "DATABASE_URL", "FRONTEND_ORIGINS"):
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setenv("ENVIRONMENT", "production")
    try:
        validate_environment()
    except RuntimeError as error:
        assert "Missing required production settings" in str(error)
    else:
        raise AssertionError("Production configuration should require deployment settings")


def test_dockerfile_uses_non_root_runtime():
    dockerfile = Path("Dockerfile").read_text(encoding="utf-8")
    assert "USER app" in dockerfile
    assert "HEALTHCHECK" in dockerfile
