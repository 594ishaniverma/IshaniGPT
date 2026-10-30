"""Initial schema"""
from alembic import op
import sqlalchemy as sa

revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None

def upgrade():
    op.create_table("users", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("name", sa.String(80), nullable=False), sa.Column("email", sa.String(254), nullable=False), sa.Column("password_hash", sa.String(256), nullable=False), sa.Column("created_at", sa.DateTime(), nullable=False))
    op.create_index("ix_users_email", "users", ["email"], unique=True)
    op.create_table("auth_tokens", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False), sa.Column("token_hash", sa.String(64), nullable=False), sa.Column("expires_at", sa.DateTime(), nullable=False))
    op.create_index("ix_auth_tokens_user_id", "auth_tokens", ["user_id"])
    op.create_index("ix_auth_tokens_token_hash", "auth_tokens", ["token_hash"], unique=True)
    op.create_table("conversations", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("thread_id", sa.String(), nullable=False), sa.Column("title", sa.String(), nullable=True), sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True), sa.Column("created_at", sa.DateTime(), nullable=True), sa.Column("updated_at", sa.DateTime(), nullable=True))
    op.create_index("ix_conversations_thread_id", "conversations", ["thread_id"], unique=True)
    op.create_index("ix_conversations_user_id", "conversations", ["user_id"])
    op.create_table("chat_messages", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("thread_id", sa.String(), nullable=True), sa.Column("role", sa.String(), nullable=True), sa.Column("content", sa.Text(), nullable=True), sa.Column("created_at", sa.DateTime(), nullable=True))
    op.create_index("ix_chat_messages_thread_id", "chat_messages", ["thread_id"])
    op.create_table("long_term_memory", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("thread_id", sa.String(), nullable=True), sa.Column("memory", sa.Text(), nullable=True), sa.Column("created_at", sa.DateTime(), nullable=True))
    op.create_index("ix_long_term_memory_thread_id", "long_term_memory", ["thread_id"])

def downgrade():
    for table in ("long_term_memory", "chat_messages", "conversations", "auth_tokens", "users"): op.drop_table(table)
