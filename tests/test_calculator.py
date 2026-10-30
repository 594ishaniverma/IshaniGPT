from tools import calculator


def test_calculator_safe_arithmetic():
    assert calculator.invoke({"expression": "2 + 3 * 4"}) == "14"


def test_calculator_rejects_python():
    assert "Calculation error" in calculator.invoke({"expression": "__import__('os').getcwd()"})
