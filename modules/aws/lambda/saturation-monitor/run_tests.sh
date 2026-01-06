#!/bin/bash
set -e

# Run tests for ECS Agent Saturation Monitor Lambda function

echo "=== ECS Agent Saturation Monitor Lambda Tests ==="
echo

# Check if we're in the right directory
if [ ! -f "lambda_function.py" ]; then
    echo "Error: lambda_function.py not found. Please run this script from the lambda module directory."
    exit 1
fi

# Create virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
echo "Activating virtual environment..."
source venv/bin/activate

# Install test dependencies
echo "Installing test dependencies..."
pip install -r test_requirements.txt

# Run unit tests with coverage
echo
echo "Running unit tests..."
python -m pytest test_lambda_function.py -v --cov=lambda_function --cov-report=term-missing --cov-report=html

# Alternative: Run with unittest if pytest not preferred
echo
echo "Alternative: Running with unittest..."
python -m unittest test_lambda_function.py -v

# Generate coverage report
echo
echo "Coverage report generated in htmlcov/index.html"

# Run specific test categories
echo
echo "Running unit tests only..."
python -m pytest -m "unit" -v || echo "No unit-specific markers found, running all tests"

echo
echo "=== Test Summary ==="
echo "✅ Unit tests completed"
echo "📊 Coverage report: htmlcov/index.html"
echo "🔍 Detailed results above"

# Deactivate virtual environment
deactivate