import ast
import math
import operator
from contextvars import ContextVar, Token
from dotenv import load_dotenv

from langchain_core.tools import tool
from langchain_tavily import TavilySearch
from database import save_memory,search_memory
from rag import retrieve_from_rag

load_dotenv()

_current_thread_id: ContextVar[str] = ContextVar("current_thread_id", default="default")


def set_current_thread_id(thread_id: str) -> Token[str]:
    return _current_thread_id.set(thread_id)


def reset_current_thread_id(token: Token[str]) -> None:
    _current_thread_id.reset(token)


web_search=TavilySearch(
    max_result=5,
    topic="general",
    search_depth="advanced"
)

_CALC_OPERATORS = {
    ast.Add: operator.add, ast.Sub: operator.sub,
    ast.Mult: operator.mul, ast.Div: operator.truediv,
    ast.FloorDiv: operator.floordiv, ast.Mod: operator.mod,
    ast.Pow: operator.pow, ast.UAdd: operator.pos, ast.USub: operator.neg,
}
_CALC_FUNCTIONS = {
    "abs": abs, "round": round, "min": min, "max": max, "sum": sum,
    "sqrt": math.sqrt, "sin": math.sin, "cos": math.cos, "tan": math.tan,
    "log": math.log, "exp": math.exp, "pow": pow,
}
_CALC_CONSTANTS = {"pi": math.pi, "e": math.e}


def _safe_calculate(node):
    if isinstance(node, ast.Expression):
        return _safe_calculate(node.body)
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
        return node.value
    if isinstance(node, ast.Name) and node.id in _CALC_CONSTANTS:
        return _CALC_CONSTANTS[node.id]
    if isinstance(node, ast.BinOp) and type(node.op) in _CALC_OPERATORS:
        left, right = _safe_calculate(node.left), _safe_calculate(node.right)
        if isinstance(node.op, ast.Pow):
            if abs(right) > 1000:
                raise ValueError("Exponent is too large")
        return _CALC_OPERATORS[type(node.op)](left, right)
    if isinstance(node, ast.UnaryOp) and type(node.op) in _CALC_OPERATORS:
        return _CALC_OPERATORS[type(node.op)](_safe_calculate(node.operand))
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in _CALC_FUNCTIONS:
        if node.keywords:
            raise ValueError("Keyword arguments are not supported")
        args = [_safe_calculate(arg) for arg in node.args]
        return _CALC_FUNCTIONS[node.func.id](*args)
    raise ValueError("Unsupported calculator expression")


@tool
def calculator(expression: str) -> str:
    """Calculate a safe arithmetic expression using +, -, *, /, %, ** and common math functions."""
    try:
        if len(expression) > 500:
            raise ValueError("Expression is too long")
        parsed = ast.parse(expression.strip().replace("^", "**"), mode="eval")
        result = _safe_calculate(parsed)
        if isinstance(result, complex) or not math.isfinite(float(result)):
            raise ValueError("Result must be a finite real number")
        return str(result)
    except Exception as error:
        return f"Calculation error: {error}"

@tool
def search_uploaded_documents(query: str) -> str:
    """
    Search uploaded documents for relevant information.
    Use this when the user asks about uploaded PDFs, DOCX, TXT, notes, files, or documents.
    """

    return retrieve_from_rag(
        query=query,
        thread_id=_current_thread_id.get()
    )




@tool
def remember_this(memory: str) -> str:
    """
    Save an important user preference or fact into long-term memory.
    Use this when the user asks you to remember something.
    """

    return save_memory(
        thread_id=_current_thread_id.get(),
        memory=memory
    )



@tool
def recall_memory(query: str) -> str:
    """
    Recall saved long-term memories about the user or this conversation.
    """

    return search_memory(
        thread_id=_current_thread_id.get(),
        query=query
    )





tools = [
    calculator,
    search_uploaded_documents,
    remember_this,
    recall_memory,
    web_search
]