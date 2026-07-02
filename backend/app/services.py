import io
import json
from collections import defaultdict
from datetime import date, datetime, timezone
from statistics import variance
from typing import Any, Iterable, Optional
from zoneinfo import ZoneInfo

from fastapi import HTTPException, WebSocket
from openpyxl import Workbook
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from sqlalchemy.orm import Session

import models


APP_TIMEZONE = ZoneInfo("Asia/Ulaanbaatar")


def utcnow_naive() -> datetime:
    return datetime.utcnow()


def app_now() -> datetime:
    return datetime.now(APP_TIMEZONE)


def app_now_naive() -> datetime:
    return app_now().replace(tzinfo=None)


def app_today() -> date:
    return app_now().date()


def to_app_naive(value: datetime) -> datetime:
    if value.tzinfo is None:
        # Naive datetime ирвэл app-ийн локал цаг гэж үзнэ.
        return value
    return value.astimezone(APP_TIMEZONE).replace(tzinfo=None)


def ensure_nonce_is_valid(
    db: Session,
    organization_id: str,
    user_id: str,
    nonce: str,
    client_timestamp: datetime,
) -> None:
    server_now = datetime.now(timezone.utc)
    ts = client_timestamp if client_timestamp.tzinfo else client_timestamp.replace(tzinfo=timezone.utc)
    diff_seconds = abs((server_now - ts).total_seconds())
    if diff_seconds > 30:
        raise HTTPException(status_code=400, detail="Timestamp outside allowed window")

    exists = db.query(models.AttendanceNonce).filter(models.AttendanceNonce.nonce == nonce).first()
    if exists:
        raise HTTPException(status_code=409, detail="Replay attack detected: nonce already used")

    db.add(
        models.AttendanceNonce(
            organization_id=organization_id,
            user_id=user_id,
            nonce=nonce,
        )
    )
    db.flush()


def compute_rssi_variance(samples: list[int]) -> Optional[float]:
    if len(samples) < 2:
        return None
    return float(variance(samples))


def detect_suspicious_rssi(samples: list[int]) -> bool:
    if len(samples) < 3:
        return False
    v = compute_rssi_variance(samples)
    return v is not None and v < 1.0


def validate_schedule_conflict(
    db: Session,
    organization_id: str,
    room_id: Optional[str],
    teacher_id: Optional[str],
    day_of_week: Optional[str],
    start_time,
    end_time,
    exclude_id: Optional[str] = None,
) -> None:
    if not (day_of_week and start_time and end_time):
        return

    query = db.query(models.ClassOrShift).filter(
        models.ClassOrShift.organization_id == organization_id,
        models.ClassOrShift.day_of_week == day_of_week,
        models.ClassOrShift.is_active == True,
    )

    if exclude_id:
        query = query.filter(models.ClassOrShift.id != exclude_id)

    candidates = query.all()
    for item in candidates:
        if not item.start_time or not item.end_time:
            continue
        overlaps = start_time < item.end_time and end_time > item.start_time
        same_room = room_id and item.room_id == room_id
        same_teacher = teacher_id and item.teacher_id == teacher_id
        if overlaps and (same_room or same_teacher):
            raise HTTPException(status_code=409, detail="Schedule conflict detected")


def serialize_model_instance(obj: Any, fields: Iterable[str]) -> str:
    data = {}
    for field in fields:
        value = getattr(obj, field, None)
        if isinstance(value, datetime):
            data[field] = value.isoformat()
        else:
            data[field] = value
    return json.dumps(data, ensure_ascii=False, default=str)


def create_excel_report(records: list[models.Attendance]) -> bytes:
    wb = Workbook()
    ws = wb.active
    ws.title = "Attendance"

    ws.append([
        "Attendance ID",
        "User ID",
        "Session ID",
        "Date",
        "Check-in",
        "Check-out",
        "Status",
        "Late Minutes",
        "RSSI",
        "Distance (m)",
        "Method",
        "Note",
    ])

    for r in records:
        ws.append([
            r.id,
            r.user_id,
            r.session_id,
            str(r.attendance_date),
            str(r.check_in_time),
            str(r.check_out_time) if r.check_out_time else "",
            r.status,
            r.late_minutes,
            r.rssi,
            r.distance_m,
            r.detection_method,
            r.note or "",
        ])

    stream = io.BytesIO()
    wb.save(stream)
    return stream.getvalue()


def create_pdf_report(title: str, records: list[models.Attendance]) -> bytes:
    stream = io.BytesIO()
    pdf = canvas.Canvas(stream, pagesize=A4)
    width, height = A4

    y = height - 40
    pdf.setFont("Helvetica-Bold", 14)
    pdf.drawString(40, y, title)
    y -= 24

    pdf.setFont("Helvetica", 9)
    for r in records:
        line = (
            f"ID:{r.id} User:{r.user_id} Session:{r.session_id} "
            f"Status:{r.status} In:{r.check_in_time} Out:{r.check_out_time or '-'}"
        )
        pdf.drawString(40, y, line[:110])
        y -= 14
        if y < 40:
            pdf.showPage()
            pdf.setFont("Helvetica", 9)
            y = height - 40

    pdf.save()
    return stream.getvalue()


class NotificationService:
    @staticmethod
    def send_push(user_id: str, title: str, body: str) -> None:
        print(f"[push] user={user_id} title={title} body={body}")


class ConnectionManager:
    def __init__(self) -> None:
        self.active_connections: dict[str, set[WebSocket]] = defaultdict(set)

    async def connect(self, organization_id: str, websocket: WebSocket) -> None:
        await websocket.accept()
        self.active_connections[organization_id].add(websocket)

    def disconnect(self, organization_id: str, websocket: WebSocket) -> None:
        if organization_id in self.active_connections:
            self.active_connections[organization_id].discard(websocket)

    async def broadcast(self, organization_id: str, message: dict[str, Any]) -> None:
        broken: list[WebSocket] = []
        for ws in self.active_connections.get(organization_id, set()):
            try:
                await ws.send_json(message)
            except Exception:
                broken.append(ws)
        for ws in broken:
            self.disconnect(organization_id, ws)
from datetime import date, datetime, timezone
from fastapi import HTTPException
from redis_client import redis_client


def validate_timestamp(client_timestamp: datetime) -> None:
    server_now = datetime.now(timezone.utc)
    ts = client_timestamp if client_timestamp.tzinfo else client_timestamp.replace(tzinfo=timezone.utc)
    diff_seconds = abs((server_now - ts).total_seconds())

    if diff_seconds > 30:
        raise HTTPException(status_code=400, detail="Timestamp outside allowed window")


def ensure_nonce_unused(user_id: str, nonce: str) -> None:
    key = f"nonce:{user_id}:{nonce}"
    if redis_client.exists(key):
        raise HTTPException(status_code=409, detail="Replay attack detected: nonce already used")

    redis_client.setex(key, 60, "used")


def ensure_not_duplicate_checkin(user_id: str, session_id: str) -> None:
    key = f"attendance:{user_id}:{session_id}"
    if redis_client.exists(key):
        raise HTTPException(status_code=400, detail="Duplicate check-in attempt")

    redis_client.setex(key, 300, "checked")


def cache_dashboard_overview(organization_id: str, month: str, payload: dict) -> None:
    key = f"dashboard:overview:{organization_id}:{month}"
    redis_client.setex(key, 60, str(payload))


def get_dashboard_overview_cache(organization_id: str, month: str):
    key = f"dashboard:overview:{organization_id}:{month}"
    return redis_client.get(key)


def clear_dashboard_cache(organization_id: str) -> None:
    pattern = f"dashboard:*:{organization_id}:*"
    for key in redis_client.scan_iter(pattern):
        redis_client.delete(key)
