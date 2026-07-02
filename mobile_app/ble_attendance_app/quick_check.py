import requests
from datetime import datetime

BASE_URL = "http://192.168.10.15:8000"

ACCOUNTS = {
    "admin": {"username": "admin", "password": "admin123"},
    "teacher": {"username": "teacher1", "password": "teacher123"},
    "student": {"username": "b221940049", "password": "student123"},
}


def print_result(name, ok, status=None, detail=""):
    icon = "✅" if ok else "❌"
    print(f"{icon} {name}", end="")
    if status is not None:
        print(f" | status={status}", end="")
    if detail:
        print(f" | {detail}", end="")
    print()


def login(role):
    try:
        r = requests.post(
            f"{BASE_URL}/auth/login",
            json=ACCOUNTS[role],
            timeout=10,
        )
        if r.status_code != 200:
            print_result(f"{role} login", False, r.status_code, r.text[:200])
            return None

        data = r.json()
        token = data.get("access_token")
        user_id = data.get("user_id")
        print_result(f"{role} login", True, r.status_code, f"user_id={user_id}")
        return {
            "token": token,
            "user_id": user_id,
            "role": data.get("role"),
            "org": data.get("organization_id"),
        }
    except Exception as e:
        print_result(f"{role} login", False, detail=str(e))
        return None


def get(path, token, name):
    try:
        r = requests.get(
            f"{BASE_URL}{path}",
            headers={"Authorization": f"Bearer {token}"},
            timeout=10,
        )
        ok = 200 <= r.status_code < 300
        detail = ""
        if not ok:
            detail = r.text[:200]
        else:
            try:
                data = r.json()
                if isinstance(data, list):
                    detail = f"items={len(data)}"
                elif isinstance(data, dict):
                    detail = f"keys={list(data.keys())[:5]}"
            except Exception:
                detail = "OK"
        print_result(name, ok, r.status_code, detail)
        return r
    except Exception as e:
        print_result(name, False, detail=str(e))
        return None


def post(path, token, payload, name):
    try:
        r = requests.post(
            f"{BASE_URL}{path}",
            headers={"Authorization": f"Bearer {token}"},
            json=payload,
            timeout=10,
        )
        ok = 200 <= r.status_code < 300
        detail = r.text[:200] if not ok else "OK"
        print_result(name, ok, r.status_code, detail)
        return r
    except Exception as e:
        print_result(name, False, detail=str(e))
        return None


def main():
    print("====== BLE ATTENDANCE QUICK CHECK ======")
    print(f"BASE_URL = {BASE_URL}")
    print()

    admin = login("admin")
    teacher = login("teacher")
    student = login("student")

    print("\n====== ADMIN TEST ======")
    if admin:
        get("/users", admin["token"], "Admin: users")
        get("/classes", admin["token"], "Admin: classes")
        get("/beacons", admin["token"], "Admin: beacons")
        get("/rooms", admin["token"], "Admin: rooms")
        get("/sessions", admin["token"], "Admin: sessions")
        get("/attendance/all", admin["token"], "Admin: attendance all")
        get("/attendance/appeals", admin["token"], "Admin: appeals")
        get("/audit-logs", admin["token"], "Admin: audit logs")
        get("/report/summary/2026-05", admin["token"], "Admin: report summary")
        get("/report/monthly/2026-05", admin["token"], "Admin: report monthly")

    print("\n====== TEACHER TEST ======")
    if teacher:
        get("/classes", teacher["token"], "Teacher: classes")
        get("/sessions", teacher["token"], "Teacher: sessions")
        get("/attendance/all", teacher["token"], "Teacher: attendance all")
        get("/attendance/appeals", teacher["token"], "Teacher: appeals")
        get("/report/summary/2026-05", teacher["token"], "Teacher: report summary")
        get("/report/monthly/2026-05", teacher["token"], "Teacher: report monthly")

    print("\n====== STUDENT TEST ======")
    if student:
        uid = student["user_id"]
        get(f"/users/{uid}", student["token"], "Student: my profile")
        get(f"/students/{uid}/classes", student["token"], "Student: my classes")
        get(f"/attendance/history/{uid}", student["token"], "Student: history")
        get("/report/summary/2026-05", student["token"], "Student: report summary")
        get("/report/monthly/2026-05", student["token"], "Student: report monthly")

    print("\n====== DONE ======")


if __name__ == "__main__":
    main()
