import hashlib
import hmac
import json
import logging
import os
import re
import secrets
import shutil
import time
from collections import defaultdict, deque
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

from fastapi import Depends, FastAPI, File, HTTPException, Request, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from database import (
    AuthToken,
    ChatMessage,
    Conversation,
    SessionLocal,
    User,
    engine,
    create_or_update_conversation,
    get_chat_history,
    init_db,
    save_chat_message,
)

logger = logging.getLogger(__name__)
PASSWORD_ITERATIONS = 310_000
TOKEN_LIFETIME = timedelta(days=30)
bearer_scheme = HTTPBearer(auto_error=False)


def validate_environment() -> None:
    environment = os.getenv("ENVIRONMENT", "development").strip().lower()
    if environment not in {"development", "test", "staging", "production"}:
        raise RuntimeError("ENVIRONMENT must be development, test, staging, or production.")

    if environment == "production":
        required = ("GOOGLE_API_KEY", "DATABASE_URL", "FRONTEND_ORIGINS")
        missing = [key for key in required if not os.getenv(key, "").strip()]
        if missing:
            raise RuntimeError(f"Missing required production settings: {', '.join(missing)}")
        if not os.getenv("FRONTEND_ORIGINS", "").split(",")[0].strip().startswith("https://"):
            raise RuntimeError("Production FRONTEND_ORIGINS must contain HTTPS origins.")


@asynccontextmanager
async def lifespan(_: FastAPI):
    validate_environment()
    init_db()
    with engine.connect() as connection:
        connection.execute(text("SELECT 1"))
    yield
    engine.dispose()


app = FastAPI(title="IshaniGPT API", version="1.0.0", lifespan=lifespan)
frontend_origins = [
    origin.strip()
    for origin in os.getenv("FRONTEND_ORIGINS", "").split(",")
    if origin.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=frontend_origins,
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["X-Request-ID"],
)

class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {"level": record.levelname, "message": record.getMessage(), "logger": record.name}
        if hasattr(record, "request_id"):
            payload["request_id"] = record.request_id
        return json.dumps(payload, default=str)

_handler = logging.StreamHandler()
_handler.setFormatter(JsonFormatter())
logging.getLogger().handlers[:] = [_handler]
logging.getLogger().setLevel(os.getenv("LOG_LEVEL", "INFO"))
_rate_windows: dict[str, deque[float]] = defaultdict(deque)

@app.middleware("http")
async def observability(request: Request, call_next):
    request_id = request.headers.get("X-Request-ID", uuid4().hex)
    started = time.monotonic()
    window = _rate_windows[request.client.host if request.client else "unknown"]
    now = time.monotonic()
    while window and now - window[0] > 60:
        window.popleft()
    limit = int(os.getenv("RATE_LIMIT_PER_MINUTE", "120"))
    if len(window) >= limit:
        return StreamingResponse(iter([json.dumps({"detail": "Rate limit exceeded."})]), status_code=429,
                                  media_type="application/json", headers={"X-Request-ID": request_id})
    window.append(now)
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    response.headers["X-Process-Time"] = f"{time.monotonic() - started:.4f}"
    logger.info("request completed", extra={"request_id": request_id})
    return response


class UserResponse(BaseModel):
    id: int
    name: str
    email: str

    model_config = ConfigDict(from_attributes=True)


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse


class SignupRequest(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    email: str = Field(max_length=254)
    password: str = Field(min_length=8, max_length=128)

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Name cannot be blank.")
        return value

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value: str) -> str:
        value = value.strip().lower()
        if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", value):
            raise ValueError("Enter a valid email address.")
        return value


class LoginRequest(BaseModel):
    email: str = Field(max_length=254)
    password: str = Field(min_length=1, max_length=128)

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value: str) -> str:
        value = value.strip().lower()
        if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", value):
            raise ValueError("Enter a valid email address.")
        return value


class ConversationResponse(BaseModel):
    thread_id: str
    title: str
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class MessageResponse(BaseModel):
    id: int
    role: str
    content: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class SendMessageRequest(BaseModel):
    content: str = Field(min_length=1, max_length=12_000)

    @field_validator("content")
    @classmethod
    def validate_content(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Message cannot be blank.")
        return value


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt,
        PASSWORD_ITERATIONS,
    )
    return f"{salt.hex()}:{digest.hex()}"


def verify_password(password: str, stored_hash: str) -> bool:
    try:
        salt_hex, digest_hex = stored_hash.split(":", maxsplit=1)
        salt = bytes.fromhex(salt_hex)
        expected_digest = bytes.fromhex(digest_hex)
    except ValueError:
        return False

    actual_digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt,
        PASSWORD_ITERATIONS,
    )
    return hmac.compare_digest(actual_digest, expected_digest)


def issue_token(db, user: User) -> AuthResponse:
    token = secrets.token_urlsafe(32)
    db.add(
        AuthToken(
            user_id=user.id,
            token_hash=hashlib.sha256(token.encode("utf-8")).hexdigest(),
            expires_at=datetime.utcnow() + TOKEN_LIFETIME,
        )
    )
    db.commit()
    return AuthResponse(access_token=token, user=UserResponse.model_validate(user))


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> User:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Please sign in to continue.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token_hash = hashlib.sha256(credentials.credentials.encode("utf-8")).hexdigest()
    db = SessionLocal()
    try:
        auth_token = (
            db.query(AuthToken)
            .filter(
                AuthToken.token_hash == token_hash,
                AuthToken.expires_at > datetime.utcnow(),
            )
            .first()
        )
        user = db.get(User, auth_token.user_id) if auth_token else None
        if user is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Your session has expired. Please sign in again.",
                headers={"WWW-Authenticate": "Bearer"},
            )
        return user
    finally:
        db.close()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}

@app.get("/ready")
def ready() -> dict[str, str]:
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
        return {"status": "ready"}
    except Exception as error:
        logger.exception("Readiness check failed")
        raise HTTPException(status_code=503, detail="Service is not ready") from error


@app.post("/auth/signup", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
def signup(request: SignupRequest) -> AuthResponse:
    db = SessionLocal()
    try:
        user = User(
            name=request.name,
            email=request.email,
            password_hash=hash_password(request.password),
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        return issue_token(db, user)
    except IntegrityError as error:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email already exists.",
        ) from error
    finally:
        db.close()


@app.post("/auth/login", response_model=AuthResponse)
def login(request: LoginRequest) -> AuthResponse:
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.email == request.email).first()
        if user is None or not verify_password(request.password, user.password_hash):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect email or password.",
            )
        return issue_token(db, user)
    finally:
        db.close()


@app.get("/auth/me", response_model=UserResponse)
def me(user: User = Depends(get_current_user)) -> User:
    return user


@app.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    user: User = Depends(get_current_user),
) -> None:
    if credentials is None:
        return
    token_hash = hashlib.sha256(credentials.credentials.encode("utf-8")).hexdigest()
    db = SessionLocal()
    try:
        db.query(AuthToken).filter(
            AuthToken.user_id == user.id,
            AuthToken.token_hash == token_hash,
        ).delete()
        db.commit()
    finally:
        db.close()


@app.get("/conversations", response_model=list[ConversationResponse])
def list_user_conversations(offset: int = 0, limit: int = 50, user: User = Depends(get_current_user)) -> list[Conversation]:
    db = SessionLocal()
    try:
        return (
            db.query(Conversation)
            .filter(Conversation.user_id == user.id)
            .order_by(Conversation.updated_at.desc())
            .offset(max(offset, 0)).limit(min(max(limit, 1), 100))
            .all()
        )
    finally:
        db.close()


@app.post(
    "/conversations",
    response_model=ConversationResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_conversation(user: User = Depends(get_current_user)) -> Conversation:
    thread_id = str(uuid4())
    create_or_update_conversation(thread_id, user_id=user.id)
    db = SessionLocal()
    try:
        return db.query(Conversation).filter(Conversation.thread_id == thread_id).one()
    finally:
        db.close()


def owned_conversation(db, thread_id: str, user_id: int) -> Conversation:
    conversation = (
        db.query(Conversation)
        .filter(
            Conversation.thread_id == thread_id,
            Conversation.user_id == user_id,
        )
        .first()
    )
    if conversation is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Chat not found.")
    return conversation


@app.get(
    "/conversations/{thread_id}/messages",
    response_model=list[MessageResponse],
)
def list_messages(
    thread_id: str,
    offset: int = 0,
    limit: int = 100,
    user: User = Depends(get_current_user),
) -> list[ChatMessage]:
    db = SessionLocal()
    try:
        owned_conversation(db, thread_id, user.id)
        history = get_chat_history(thread_id)
        return history[max(offset, 0):max(offset, 0) + min(max(limit, 1), 500)]
    finally:
        db.close()


@app.post(
    "/conversations/{thread_id}/messages",
    response_model=MessageResponse,
    status_code=status.HTTP_201_CREATED,
)
def send_message(
    thread_id: str,
    request: SendMessageRequest,
    user: User = Depends(get_current_user),
) -> ChatMessage:
    db = SessionLocal()
    try:
        owned_conversation(db, thread_id, user.id)
    finally:
        db.close()

    save_chat_message(thread_id, "user", request.content)
    try:
        from agents import get_agent
        from langchain_core.messages import HumanMessage
        from tools import reset_current_thread_id, set_current_thread_id

        context_token = set_current_thread_id(thread_id)
        try:
            result = get_agent().invoke(
                {"messages": [HumanMessage(content=request.content)]},
                config={"configurable": {"thread_id": thread_id}},
            )
        finally:
            reset_current_thread_id(context_token)

        response_content = result["messages"][-1].content
        if isinstance(response_content, list):
            response_content = "\n".join(
                block.get("text", "") if isinstance(block, dict) else str(block)
                for block in response_content
            ).strip()
        if not isinstance(response_content, str) or not response_content.strip():
            raise ValueError("The assistant returned an empty response.")
    except Exception as error:
        logger.exception("Assistant response failed for conversation %s", thread_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="IshaniGPT could not generate a response. Please try again.",
        ) from error

    save_chat_message(thread_id, "assistant", response_content)
    db = SessionLocal()
    try:
        return (
            db.query(ChatMessage)
            .filter(ChatMessage.thread_id == thread_id, ChatMessage.role == "assistant")
            .order_by(ChatMessage.created_at.desc(), ChatMessage.id.desc())
            .first()
        )
    finally:
        db.close()


@app.post("/conversations/{thread_id}/upload")
def upload_document(thread_id: str, file: UploadFile = File(...), user: User = Depends(get_current_user)) -> dict:
    db = SessionLocal()
    try:
        owned_conversation(db, thread_id, user.id)
    finally:
        db.close()
    allowed = {".pdf", ".docx", ".txt", ".md", ".py", ".csv"}
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in allowed:
        raise HTTPException(status_code=400, detail="Unsupported file type")
    destination = Path(os.getenv("UPLOAD_DIR", "uploads")) / f"{thread_id}_{uuid4().hex}{suffix}"
    destination.parent.mkdir(parents=True, exist_ok=True)
    size = 0
    try:
        with destination.open("wb") as output:
            while chunk := file.file.read(1024 * 1024):
                size += len(chunk)
                if size > 20 * 1024 * 1024:
                    raise HTTPException(status_code=413, detail="File exceeds 20 MB limit")
                output.write(chunk)
        from rag import add_document_to_rag
        return add_document_to_rag(str(destination), thread_id)
    finally:
        destination.unlink(missing_ok=True)


@app.post("/conversations/{thread_id}/messages/stream")
def stream_message(thread_id: str, request: SendMessageRequest, user: User = Depends(get_current_user)):
    db = SessionLocal()
    try:
        owned_conversation(db, thread_id, user.id)
    finally:
        db.close()
    save_chat_message(thread_id, "user", request.content)

    def events():
        try:
            from agents import get_agent
            from langchain_core.messages import HumanMessage
            from tools import reset_current_thread_id, set_current_thread_id
            context_token = set_current_thread_id(thread_id)
            pieces = []
            try:
                for chunk in get_agent().stream(
                    {"messages": [HumanMessage(content=request.content)]},
                    config={"configurable": {"thread_id": thread_id}},
                    stream_mode="messages",
                ):
                    payload = chunk[0] if isinstance(chunk, tuple) else chunk
                    content = getattr(payload, "content", "") if payload else ""
                    if isinstance(content, list):
                        content = "".join(block.get("text", "") if isinstance(block, dict) else str(block) for block in content)
                    if content:
                        pieces.append(content)
                        yield f"data: {json.dumps({'delta': content})}\n\n"
            finally:
                reset_current_thread_id(context_token)
            final = "".join(pieces).strip()
            if final:
                save_chat_message(thread_id, "assistant", final)
            yield "data: [DONE]\n\n"
        except Exception:
            logger.exception("Streaming assistant response failed")
            yield "data: {\"error\": \"IshaniGPT could not generate a response.\"}\n\n"
    return StreamingResponse(events(), media_type="text/event-stream", headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})
