#!/bin/bash
set -e

echo "🚀 Starting E2E Test Environment"
echo "================================"

# Check if database is running
if ! pg_isready -h localhost -p 5432 -U gastos 2>/dev/null; then
    echo "❌ PostgreSQL is not running on localhost:5432"
    echo "Please start the database first"
    exit 1
fi

# Navigate to backend directory (from tests/e2e)
cd ../../

# Build the backend if needed
if [ ! -f "./gastos-api" ]; then
    echo "📦 Building backend..."
    go build -o gastos-api ./cmd/api
fi

# Set environment variables for local testing
export DATABASE_URL="postgres://gastos:gastos_dev_password@localhost:5432/gastos?sslmode=disable"
export STATIC_DIR="../frontend"
export RATE_LIMIT_ENABLED="false"
export SESSION_COOKIE_SECURE="false"
export EMAIL_PROVIDER="noop"

# Start backend and redirect logs to /tmp/backend.log
echo "🔧 Starting backend server..."
./gastos-api > /tmp/backend.log 2>&1 &
BACKEND_PID=$!

# Wait for backend to be healthy
echo "⏳ Waiting for backend to be ready..."
sleep 3
timeout 30 bash -c 'until curl -sf http://localhost:8080/health > /dev/null; do sleep 1; done' || {
    echo "❌ Backend failed to start"
    kill $BACKEND_PID 2>/dev/null || true
    exit 1
}

echo "✅ Backend is healthy"
echo ""

# Run the tests
echo "🧪 Running E2E tests..."
cd tests
npm run test:e2e

# Store test result
TEST_RESULT=$?

# Cleanup
echo ""
echo "🧹 Cleaning up..."
kill $BACKEND_PID 2>/dev/null || true

if [ $TEST_RESULT -eq 0 ]; then
    echo "✅ All tests passed!"
else
    echo "❌ Some tests failed"
fi

exit $TEST_RESULT
