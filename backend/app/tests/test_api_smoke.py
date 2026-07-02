import os
from pathlib import Path

TEST_DB = Path("/private/tmp/ble_attendance_pytest.db")

if TEST_DB.exists():
    TEST_DB.unlink()

os.environ["DATABASE_URL"] = f"sqlite:///{TEST_DB}"
os.environ["REDIS_URL"] = "redis://localhost:6379/0"
os.environ["SECRET_KEY"] = "pytest-secret-key-with-enough-length"
os.environ["ADMIN_PASSWORD"] = "pytest-admin-password"
os.environ["TEACHER_PASSWORD"] = "pytest-teacher-password"
os.environ["STUDENT_PASSWORD"] = "pytest-student-password"

from fastapi import HTTPException
from fastapi.testclient import TestClient

import main
import schemas
import seed


client = TestClient(main.app)


def setup_module():
    main.Base.metadata.create_all(bind=main.engine)
    seed.seed()


def test_health_endpoint():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_protected_endpoint_requires_auth():
    response = client.get("/attendance/all")
    assert response.status_code == 401


def test_admin_login_and_users_endpoint():
    login = client.post(
        "/auth/login",
        json={"username": "admin", "password": "pytest-admin-password"},
    )
    assert login.status_code == 200

    token = login.json()["access_token"]
    users = client.get("/users", headers={"Authorization": f"Bearer {token}"})
    assert users.status_code == 200
    assert len(users.json()) >= 3


def test_ble_signal_quality_rejects_missing_samples():
    body = schemas.AttendanceRequest(
        user_id="B221940049",
        session_id="SESSION002",
        device_uuid="DEVICE_B221940049",
        beacon_uuid="BLE Advertiser",
        rssi=-60,
        distance=1.5,
        rssi_samples=[-60, -61],
        client_timestamp="2026-05-10T00:00:00Z",
        nonce="nonce-123456",
    )

    try:
        main.ensure_ble_signal_quality(body)
    except HTTPException as exc:
        assert exc.status_code == 400
    else:
        raise AssertionError("Expected missing RSSI samples to be rejected")
