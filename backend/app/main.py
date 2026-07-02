from collections import defaultdict
from datetime import date, datetime, timedelta, timezone, time
from typing import Optional
import json

from fastapi import (
    Depends,
    FastAPI,
    HTTPException,
    Request,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

import models
import schemas
import services
from config import settings
from auth import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    refresh_token_expiry,
    verify_password,
)
from database import Base, engine
from deps import (
    check_rate_limit,
    ensure_same_org,
    get_current_user,
    get_db,
    require_roles,
)
from redis_client import redis_client

if settings.auto_create_tables:
    Base.metadata.create_all(bind=engine)

app = FastAPI(title="BLE Attendance API", version="1.2.0")

# Demo/LAN орчинд тохиромжтой. Production дээр frontend domain-уудаар хязгаарлах.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept"],
)

manager = services.ConnectionManager()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def invalidate_dashboard_cache(organization_id: str):
    pattern = f"dashboard:{organization_id}:*"
    for key in redis_client.scan_iter(pattern):
        redis_client.delete(key)


def parse_month(month: str) -> tuple[int, int]:
    try:
        year_s, month_s = month.split("-")
        year, mon = int(year_s), int(month_s)
        if mon < 1 or mon > 12:
            raise ValueError
        return year, mon
    except ValueError:
        raise HTTPException(status_code=400, detail="month формат буруу байна (YYYY-MM)")


def current_daily_session_ids(session_id: str, at: datetime) -> list[str]:
    today_key = at.date().strftime("%Y%m%d")
    ids = [session_id]
    if "_" not in session_id:
        ids.append(f"{session_id}_{today_key}")
    return ids


ATTENDANCE_ROLES = ("student", "teacher")


def ensure_attendance_allowed(user: models.User) -> None:
    if user.role not in ATTENDANCE_ROLES:
        raise HTTPException(
            status_code=403,
            detail="Зөвхөн student болон teacher хэрэглэгч BLE ирц бүртгүүлэх боломжтой",
        )


def attendance_scope_query(db: Session, organization_id: str):
    return (
        db.query(models.Attendance)
        .join(models.User, models.Attendance.user_id == models.User.id)
        .filter(
            models.Attendance.organization_id == organization_id,
            models.User.role.in_(ATTENDANCE_ROLES),
        )
    )


def restrict_teacher_attendance_query(query, current_user: models.User):
    """Teacher хэрэглэгч зөвхөн өөрийн заадаг class/session-ийн ирцийг харна."""
    if current_user.role == "teacher":
        query = query.filter(
            models.Attendance.session.has(
                models.AttendanceSession.class_or_shift.has(
                    models.ClassOrShift.teacher_id == current_user.id
                )
            )
        )
    return query


def restrict_teacher_session_query(query, current_user: models.User):
    """Teacher хэрэглэгч зөвхөн өөрийн заадаг session-үүдийг харна."""
    if current_user.role == "teacher":
        query = query.filter(
            models.AttendanceSession.class_or_shift.has(
                models.ClassOrShift.teacher_id == current_user.id
            )
        )
    return query


def teacher_id_for_filter(current_user: models.User) -> Optional[str]:
    return current_user.id if current_user.role == "teacher" else None


def ensure_session_time_allowed(session: models.AttendanceSession, at: datetime) -> None:
    if not session.start_time or not session.end_time:
        return

    now_time = at.time()
    if not (session.start_time <= now_time <= session.end_time):
        raise HTTPException(
            status_code=400,
            detail="Session цагийн хүрээнээс гадуур байна",
        )


def ensure_student_enrolled(
    db: Session,
    user: models.User,
    class_or_shift_id: str,
) -> None:
    if user.role != "student":
        return

    enrolled = (
        db.query(models.ClassStudent)
        .filter(
            models.ClassStudent.organization_id == user.organization_id,
            models.ClassStudent.class_or_shift_id == class_or_shift_id,
            models.ClassStudent.user_id == user.id,
        )
        .first()
    )
    if not enrolled:
        raise HTTPException(
            status_code=403,
            detail="Энэ хичээл/ээлжид бүртгэлгүй хэрэглэгч байна",
        )


def ensure_distance_allowed(beacon: models.Beacon, distance: Optional[float]) -> None:
    if distance is None:
        return
    allowed = beacon.threshold_distance or 3.0
    if distance > allowed:
        raise HTTPException(
            status_code=400,
            detail=f"Beacon-оос хэт хол байна: {distance:.2f}m > {allowed:.2f}m",
        )


def ensure_ble_signal_quality(body: schemas.AttendanceRequest) -> None:
    if body.rssi is None or body.distance is None:
        raise HTTPException(
            status_code=400,
            detail="BLE RSSI болон distance утга заавал шаардлагатай",
        )

    if len(body.rssi_samples) < 3:
        raise HTTPException(
            status_code=400,
            detail="BLE дохионы чанар шалгахад дор хаяж 3 RSSI sample шаардлагатай",
        )

    avg = sum(body.rssi_samples) / len(body.rssi_samples)
    if abs(avg - body.rssi) > 12:
        raise HTTPException(
            status_code=400,
            detail="RSSI sample болон үндсэн RSSI хоорондын зөрүү хэт их байна",
        )


def get_registered_active_device(
    db: Session,
    *,
    user_id: str,
    device_uuid: str,
) -> models.Device:
    """BLE ирцэд зөвхөн тухайн хэрэглэгчийн баталгаажсан, идэвхтэй төхөөрөмжийг зөвшөөрнө."""
    device = (
        db.query(models.Device)
        .filter(
            models.Device.uuid == device_uuid,
            models.Device.user_id == user_id,
            models.Device.is_registered == True,
            models.Device.is_active == True,
        )
        .first()
    )
    if not device:
        raise HTTPException(status_code=403, detail="Баталгаажсан идэвхтэй төхөөрөмж олдсонгүй")
    return device


def find_active_beacon_for_attendance(
    db: Session,
    *,
    organization_id: str,
    beacon_uuid: str,
    major: Optional[str] = None,
    minor: Optional[str] = None,
) -> models.Beacon:
    """
    Beacon-ийг UUID + major/minor-аар аль болох нарийвчилж хайна.
    Ингэснээр ижил UUID-тэй өөр beacon санамсаргүй сонгогдохоос хамгаална.
    """
    query = db.query(models.Beacon).filter(
        models.Beacon.uuid == beacon_uuid,
        models.Beacon.organization_id == organization_id,
        models.Beacon.is_active == True,
    )

    if major is not None:
        query = query.filter(models.Beacon.major == major)
    if minor is not None:
        query = query.filter(models.Beacon.minor == minor)

    beacon = query.first()
    if not beacon:
        raise HTTPException(status_code=404, detail="Beacon олдсонгүй")
    return beacon


def apply_attendance_filters(
    query,
    *,
    class_id: Optional[str] = None,
    session_id: Optional[str] = None,
    user_id: Optional[str] = None,
    status: Optional[str] = None,
    from_date: Optional[date] = None,
    to_date: Optional[date] = None,
):
    from sqlalchemy import or_

    if class_id:
        query = query.join(models.AttendanceSession).filter(
            models.AttendanceSession.class_or_shift_id == class_id
        )

    if session_id:
        if "_" in session_id:
            query = query.filter(models.Attendance.session_id == session_id)
        else:
            query = query.filter(
                or_(
                    models.Attendance.session_id == session_id,
                    models.Attendance.session_id.like(f"{session_id}_%"),
                )
            )

    if user_id:
        query = query.filter(models.Attendance.user_id == user_id)
    if status:
        query = query.filter(models.Attendance.status == status)
    if from_date:
        query = query.filter(models.Attendance.attendance_date >= from_date)
    if to_date:
        query = query.filter(models.Attendance.attendance_date <= to_date)

    return query


def log_audit(
    db: Session,
    *,
    organization_id: str,
    actor_user_id: Optional[str],
    action: str,
    entity_type: str,
    entity_id: str,
    old_value: Optional[str] = None,
    new_value: Optional[str] = None,
    reason: Optional[str] = None,
    request: Optional[Request] = None,
) -> None:
    db.add(
        models.AuditLog(
            organization_id=organization_id,
            actor_user_id=actor_user_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            old_value=old_value,
            new_value=new_value,
            reason=reason,
            ip_address=request.client.host if request and request.client else None,
        )
    )

DAY_NAME_MAP = {
    "monday": "Monday",
    "tuesday": "Tuesday",
    "wednesday": "Wednesday",
    "thursday": "Thursday",
    "friday": "Friday",
    "saturday": "Saturday",
    "sunday": "Sunday",
    "даваа": "Monday",
    "мягмар": "Tuesday",
    "лхагва": "Wednesday",
    "пүрэв": "Thursday",
    "баасан": "Friday",
    "бямба": "Saturday",
    "ням": "Sunday",
}


def normalize_day_name(value: Optional[str]) -> Optional[str]:
    if not value:
        return None
    raw = value.strip()
    if not raw:
        return None
    return DAY_NAME_MAP.get(raw.lower(), raw)


def app_day_name(value: date) -> str:
    return value.strftime("%A")


def is_class_scheduled_on_date(cls: models.ClassOrShift, target_date: date) -> bool:
    if not cls.is_active:
        return False

    if not cls.day_of_week or not cls.start_time or not cls.end_time:
        return False

    class_day = normalize_day_name(cls.day_of_week)
    if class_day != app_day_name(target_date):
        return False

    if cls.semester_start_date and target_date < cls.semester_start_date:
        return False

    if cls.semester_end_date and target_date > cls.semester_end_date:
        return False

    return True


def daily_session_id_for_class(class_id: str, target_date: date) -> str:
    return f"{class_id}_{target_date.strftime('%Y%m%d')}"


def get_or_create_daily_session_for_class(
    db: Session,
    cls: models.ClassOrShift,
    target_date: date,
) -> models.AttendanceSession:
    session_id = daily_session_id_for_class(cls.id, target_date)

    session = (
        db.query(models.AttendanceSession)
        .filter(
            models.AttendanceSession.id == session_id,
            models.AttendanceSession.organization_id == cls.organization_id,
        )
        .first()
    )

    if session:
        return session

    session = models.AttendanceSession(
        id=session_id,
        organization_id=cls.organization_id,
        class_or_shift_id=cls.id,
        beacon_id=cls.beacon_id,
        session_date=target_date,
        start_time=cls.start_time,
        end_time=cls.end_time,
        is_open=True,
    )

    db.add(session)
    db.flush()

    return session

# ---------------------------------------------------------------------------
# Weekly class schedule / active session helpers
# ---------------------------------------------------------------------------

DAY_NAME_MAP = {
    # English
    "monday": "Monday",
    "tuesday": "Tuesday",
    "wednesday": "Wednesday",
    "thursday": "Thursday",
    "friday": "Friday",
    "saturday": "Saturday",
    "sunday": "Sunday",

    # Mongolian
    "даваа": "Monday",
    "даваа гараг": "Monday",
    "мягмар": "Tuesday",
    "мягмар гараг": "Tuesday",
    "лхагва": "Wednesday",
    "лхагва гараг": "Wednesday",
    "пүрэв": "Thursday",
    "пүрэв гараг": "Thursday",
    "баасан": "Friday",
    "баасан гараг": "Friday",
    "бямба": "Saturday",
    "бямба гараг": "Saturday",
    "ням": "Sunday",
    "ням гараг": "Sunday",
}


def normalize_day_name(value: Optional[str]) -> Optional[str]:
    """
    day_of_week утгыг нэг стандарт хэлбэрт оруулна.
    Жишээ:
      monday / Monday / даваа / даваа гараг -> Monday
    """
    if not value:
        return None

    raw = value.strip()
    if not raw:
        return None

    return DAY_NAME_MAP.get(raw.lower(), raw)


def app_day_name(value: date) -> str:
    """
    Огнооноос гарагийн нэр авна.
    Python strftime("%A") нь Monday, Tuesday гэх мэт буцаана.
    """
    return value.strftime("%A")


def is_class_scheduled_on_date(
    cls: models.ClassOrShift,
    target_date: date,
) -> bool:
    """
    Тухайн class/shift өгөгдсөн огноонд орох эсэхийг шалгана.

    Шалгах нөхцөл:
    - class active байх
    - day_of_week, start_time, end_time бөглөгдсөн байх
    - target_date-ийн гараг class.day_of_week-тэй таарах
    - semester_start_date байвал түүнээс өмнө биш байх
    - semester_end_date байвал түүнээс хойш биш байх
    """
    if not cls.is_active:
        return False

    if not cls.day_of_week or not cls.start_time or not cls.end_time:
        return False

    class_day = normalize_day_name(cls.day_of_week)
    today_day = app_day_name(target_date)

    if class_day != today_day:
        return False

    if getattr(cls, "semester_start_date", None):
        if target_date < cls.semester_start_date:
            return False

    if getattr(cls, "semester_end_date", None):
        if target_date > cls.semester_end_date:
            return False

    return True


def daily_session_id_for_class(class_id: str, target_date: date) -> str:
    """
    Class ID + огнооноос тухайн өдрийн session ID үүсгэнэ.
    Жишээ:
      CLASS004 + 2026-02-02 -> CLASS004_20260202
    """
    return f"{class_id}_{target_date.strftime('%Y%m%d')}"


def get_or_create_daily_session_for_class(
    db: Session,
    cls: models.ClassOrShift,
    target_date: date,
) -> models.AttendanceSession:
    """
    Тухайн өдрийн session байвал буцаана.
    Байхгүй бол class-ийн schedule-аас автоматаар үүсгэнэ.
    """
    session_id = daily_session_id_for_class(cls.id, target_date)

    session = (
        db.query(models.AttendanceSession)
        .filter(
            models.AttendanceSession.id == session_id,
            models.AttendanceSession.organization_id == cls.organization_id,
        )
        .first()
    )

    if session:
        return session

    session = models.AttendanceSession(
        id=session_id,
        organization_id=cls.organization_id,
        class_or_shift_id=cls.id,
        beacon_id=cls.beacon_id,
        session_date=target_date,
        start_time=cls.start_time,
        end_time=cls.end_time,
        is_open=True,
    )

    db.add(session)
    db.flush()

    return session
# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

@app.post("/auth/login", response_model=schemas.LoginResponse)
def login(body: schemas.LoginRequest, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.username == body.username).first()
    if not user or not verify_password(body.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Нэвтрэх нэр эсвэл нууц үг буруу байна")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Хэрэглэгч идэвхгүй байна")

    access_token = create_access_token(user.id, user.role, user.organization_id)
    refresh_token = create_refresh_token()

    db.add(
        models.RefreshToken(
            user_id=user.id,
            token=refresh_token,
            expires_at=refresh_token_expiry(),
        )
    )
    db.commit()

    return schemas.LoginResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user_id=user.id,
        role=user.role,
        organization_id=user.organization_id,
    )


@app.post("/auth/refresh", response_model=schemas.LoginResponse)
def refresh(body: schemas.RefreshRequest, db: Session = Depends(get_db)):
    token_row = (
        db.query(models.RefreshToken)
        .filter(
            models.RefreshToken.token == body.refresh_token,
            models.RefreshToken.revoked_at == None,
        )
        .first()
    )
    if not token_row:
        raise HTTPException(status_code=401, detail="Refresh token хүчингүй байна")

    now = datetime.now(timezone.utc)
    expires = token_row.expires_at
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=timezone.utc)

    if now > expires:
        raise HTTPException(status_code=401, detail="Refresh token хугацаа дууссан")

    user = db.query(models.User).filter(models.User.id == token_row.user_id).first()
    if not user or not user.is_active:
        raise HTTPException(status_code=403, detail="Хэрэглэгч олдсонгүй эсвэл идэвхгүй байна")

    token_row.revoked_at = services.utcnow_naive()

    new_access = create_access_token(user.id, user.role, user.organization_id)
    new_refresh = create_refresh_token()

    db.add(
        models.RefreshToken(
            user_id=user.id,
            token=new_refresh,
            expires_at=refresh_token_expiry(),
        )
    )
    db.commit()

    return schemas.LoginResponse(
        access_token=new_access,
        refresh_token=new_refresh,
        user_id=user.id,
        role=user.role,
        organization_id=user.organization_id,
    )


@app.post("/auth/logout", response_model=schemas.MessageResponse)
def logout(
    body: schemas.LogoutRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    token_row = (
        db.query(models.RefreshToken)
        .filter(models.RefreshToken.token == body.refresh_token)
        .first()
    )
    if token_row:
        token_row.revoked_at = services.utcnow_naive()
        db.commit()

    return schemas.MessageResponse(message="Амжилттай гарлаа")


# ---------------------------------------------------------------------------
# Users
# ---------------------------------------------------------------------------

@app.get("/users", response_model=list[schemas.UserOut])
def list_users(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin")),
):
    return (
        db.query(models.User)
        .filter(models.User.organization_id == current_user.organization_id)
        .all()
    )


@app.post("/users", response_model=schemas.UserOut)
def create_user(
    body: schemas.UserCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin")),
):
    ensure_same_org(current_user, body.organization_id)

    if db.query(models.User).filter(models.User.id == body.id).first():
        raise HTTPException(status_code=409, detail="Хэрэглэгчийн ID давхардаж байна")
    if db.query(models.User).filter(models.User.username == body.username).first():
        raise HTTPException(status_code=409, detail="Username давхардаж байна")

    user = models.User(
        **{k: v for k, v in body.model_dump().items() if k != "password"},
        hashed_password=hash_password(body.password),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@app.get("/users/{user_id}", response_model=schemas.UserOut)
def get_user(
    user_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if current_user.role not in ("admin", "teacher") and current_user.id != user_id:
        raise HTTPException(status_code=403, detail="Хандах эрх байхгүй")

    user = (
        db.query(models.User)
        .filter(
            models.User.id == user_id,
            models.User.organization_id == current_user.organization_id,
        )
        .first()
    )
    if not user:
        raise HTTPException(status_code=404, detail="Хэрэглэгч олдсонгүй")
    return user


@app.patch("/users/{user_id}", response_model=schemas.UserOut)
def update_user(
    user_id: str,
    body: schemas.UserUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin")),
):
    user = (
        db.query(models.User)
        .filter(
            models.User.id == user_id,
            models.User.organization_id == current_user.organization_id,
        )
        .first()
    )
    if not user:
        raise HTTPException(status_code=404, detail="Хэрэглэгч олдсонгүй")

    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(user, field, value)

    db.commit()
    db.refresh(user)
    return user


# ---------------------------------------------------------------------------
# Devices
# ---------------------------------------------------------------------------

@app.get("/devices", response_model=list[schemas.DeviceOut])
def list_devices(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin")),
):
    return (
        db.query(models.Device)
        .join(models.User)
        .filter(models.User.organization_id == current_user.organization_id)
        .all()
    )


@app.post("/devices", response_model=schemas.DeviceOut)
def create_device(
    body: schemas.DeviceCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin")),
):
    user = (
        db.query(models.User)
        .filter(
            models.User.id == body.user_id,
            models.User.organization_id == current_user.organization_id,
        )
        .first()
    )
    if not user:
        raise HTTPException(status_code=404, detail="Хэрэглэгч олдсонгүй")

    if db.query(models.Device).filter(models.Device.uuid == body.uuid).first():
        raise HTTPException(status_code=409, detail="Device UUID давхардаж байна")

    device = models.Device(**body.model_dump())
    db.add(device)
    db.commit()
    db.refresh(device)
    return device


@app.patch("/devices/{device_id}", response_model=schemas.DeviceOut)
def update_device(
    device_id: int,
    body: schemas.DeviceUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin")),
):
    device = (
        db.query(models.Device)
        .join(models.User)
        .filter(
            models.Device.id == device_id,
            models.User.organization_id == current_user.organization_id,
        )
        .first()
    )
    if not device:
        raise HTTPException(status_code=404, detail="Төхөөрөмж олдсонгүй")

    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(device, field, value)

    db.commit()
    db.refresh(device)
    return device


# ---------------------------------------------------------------------------
# Rooms
# ---------------------------------------------------------------------------

@app.get("/rooms", response_model=list[schemas.RoomOut])
def list_rooms(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    return (
        db.query(models.Room)
        .filter(models.Room.organization_id == current_user.organization_id)
        .all()
    )


@app.post("/rooms", response_model=schemas.RoomOut)
def create_room(
    body: schemas.RoomCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin")),
):
    ensure_same_org(current_user, body.organization_id)

    if db.query(models.Room).filter(models.Room.id == body.id).first():
        raise HTTPException(status_code=409, detail="Room ID давхардаж байна")

    room = models.Room(**body.model_dump())
    db.add(room)
    db.commit()
    db.refresh(room)
    return room


@app.patch("/rooms/{room_id}", response_model=schemas.RoomOut)
def update_room(
    room_id: str,
    body: schemas.RoomUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin")),
):
    room = (
        db.query(models.Room)
        .filter(
            models.Room.id == room_id,
            models.Room.organization_id == current_user.organization_id,
        )
        .first()
    )
    if not room:
        raise HTTPException(status_code=404, detail="Өрөө олдсонгүй")

    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(room, field, value)

    db.commit()
    db.refresh(room)
    return room


# ---------------------------------------------------------------------------
# Beacons
# ---------------------------------------------------------------------------

@app.get("/beacons", response_model=list[schemas.BeaconOut])
def list_beacons(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    return (
        db.query(models.Beacon)
        .filter(models.Beacon.organization_id == current_user.organization_id)
        .all()
    )


@app.post("/beacons", response_model=schemas.BeaconOut)
def create_beacon(
    body: schemas.BeaconCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin")),
):
    ensure_same_org(current_user, body.organization_id)

    if db.query(models.Beacon).filter(models.Beacon.id == body.id).first():
        raise HTTPException(status_code=409, detail="Beacon ID давхардаж байна")

    beacon = models.Beacon(**body.model_dump())
    db.add(beacon)
    db.commit()
    db.refresh(beacon)
    return beacon


@app.patch("/beacons/{beacon_id}", response_model=schemas.BeaconOut)
def update_beacon(
    beacon_id: str,
    body: schemas.BeaconUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin")),
):
    beacon = (
        db.query(models.Beacon)
        .filter(
            models.Beacon.id == beacon_id,
            models.Beacon.organization_id == current_user.organization_id,
        )
        .first()
    )
    if not beacon:
        raise HTTPException(status_code=404, detail="Beacon олдсонгүй")

    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(beacon, field, value)

    db.commit()
    db.refresh(beacon)
    return beacon


# ---------------------------------------------------------------------------
# Classes / Shifts
# ---------------------------------------------------------------------------

@app.get("/classes", response_model=list[schemas.ClassOrShiftOut])
def list_classes(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    return (
        db.query(models.ClassOrShift)
        .filter(models.ClassOrShift.organization_id == current_user.organization_id)
        .all()
    )


@app.post("/classes", response_model=schemas.ClassOrShiftOut)
def create_class(
    body: schemas.ClassOrShiftCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin")),
):
    ensure_same_org(current_user, body.organization_id)

    if db.query(models.ClassOrShift).filter(models.ClassOrShift.id == body.id).first():
        raise HTTPException(status_code=409, detail="Class ID давхардаж байна")

    services.validate_schedule_conflict(
        db,
        organization_id=body.organization_id,
        room_id=body.room_id,
        teacher_id=body.teacher_id,
        day_of_week=body.day_of_week,
        start_time=body.start_time,
        end_time=body.end_time,
    )

    cls = models.ClassOrShift(**body.model_dump())
    db.add(cls)
    db.commit()
    db.refresh(cls)
    return cls


@app.patch("/classes/{class_id}", response_model=schemas.ClassOrShiftOut)
def update_class(
    class_id: str,
    body: schemas.ClassOrShiftUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin")),
):
    cls = (
        db.query(models.ClassOrShift)
        .filter(
            models.ClassOrShift.id == class_id,
            models.ClassOrShift.organization_id == current_user.organization_id,
        )
        .first()
    )
    if not cls:
        raise HTTPException(status_code=404, detail="Хичээл олдсонгүй")

    merged_room_id = body.room_id if body.room_id is not None else cls.room_id
    merged_teacher_id = body.teacher_id if body.teacher_id is not None else cls.teacher_id
    merged_day = body.day_of_week if body.day_of_week is not None else cls.day_of_week
    merged_start = body.start_time if body.start_time is not None else cls.start_time
    merged_end = body.end_time if body.end_time is not None else cls.end_time

    services.validate_schedule_conflict(
        db,
        organization_id=current_user.organization_id,
        room_id=merged_room_id,
        teacher_id=merged_teacher_id,
        day_of_week=merged_day,
        start_time=merged_start,
        end_time=merged_end,
        exclude_id=cls.id,
    )

    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(cls, field, value)

    db.commit()
    db.refresh(cls)
    return cls


# ---------------------------------------------------------------------------
# Class enrollments
# ---------------------------------------------------------------------------

@app.get("/classes/{class_id}/students", response_model=list[schemas.ClassStudentOut])
def list_class_students(
    class_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin", "teacher")),
):
    cls = (
        db.query(models.ClassOrShift)
        .filter(
            models.ClassOrShift.id == class_id,
            models.ClassOrShift.organization_id == current_user.organization_id,
        )
        .first()
    )
    if not cls:
        raise HTTPException(status_code=404, detail="Хичээл олдсонгүй")
    if current_user.role == "teacher" and cls.teacher_id != current_user.id:
        raise HTTPException(status_code=403, detail="Зөвхөн өөрийн хичээлийн оюутнуудыг харна")

    return (
        db.query(models.ClassStudent)
        .filter(
            models.ClassStudent.organization_id == current_user.organization_id,
            models.ClassStudent.class_or_shift_id == class_id,
        )
        .order_by(models.ClassStudent.created_at.desc())
        .all()
    )


@app.post("/classes/{class_id}/students", response_model=schemas.ClassStudentOut)
def add_class_student(
    class_id: str,
    body: schemas.ClassStudentCreate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin", "teacher")),
):
    cls = (
        db.query(models.ClassOrShift)
        .filter(
            models.ClassOrShift.id == class_id,
            models.ClassOrShift.organization_id == current_user.organization_id,
        )
        .first()
    )
    if not cls:
        raise HTTPException(status_code=404, detail="Хичээл олдсонгүй")
    if current_user.role == "teacher" and cls.teacher_id != current_user.id:
        raise HTTPException(status_code=403, detail="Зөвхөн өөрийн хичээлд оюутан нэмнэ")

    student = (
        db.query(models.User)
        .filter(
            models.User.id == body.user_id,
            models.User.organization_id == current_user.organization_id,
            models.User.role == "student",
            models.User.is_active == True,
        )
        .first()
    )
    if not student:
        raise HTTPException(status_code=404, detail="Идэвхтэй student хэрэглэгч олдсонгүй")

    existing = (
        db.query(models.ClassStudent)
        .filter(
            models.ClassStudent.class_or_shift_id == class_id,
            models.ClassStudent.user_id == body.user_id,
        )
        .first()
    )
    if existing:
        return existing

    enrollment = models.ClassStudent(
        organization_id=current_user.organization_id,
        class_or_shift_id=class_id,
        user_id=body.user_id,
    )
    db.add(enrollment)
    db.flush()

    log_audit(
        db,
        organization_id=current_user.organization_id,
        actor_user_id=current_user.id,
        action="enroll_student",
        entity_type="class_student",
        entity_id=f"{class_id}:{body.user_id}",
        new_value=services.serialize_model_instance(enrollment, ["class_or_shift_id", "user_id"]),
        reason="student enrolled to class",
        request=request,
    )

    db.commit()
    db.refresh(enrollment)
    return enrollment


@app.delete("/classes/{class_id}/students/{user_id}", response_model=schemas.MessageResponse)
def remove_class_student(
    class_id: str,
    user_id: str,
    request: Request,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin", "teacher")),
):
    cls = (
        db.query(models.ClassOrShift)
        .filter(
            models.ClassOrShift.id == class_id,
            models.ClassOrShift.organization_id == current_user.organization_id,
        )
        .first()
    )
    if not cls:
        raise HTTPException(status_code=404, detail="Хичээл олдсонгүй")
    if current_user.role == "teacher" and cls.teacher_id != current_user.id:
        raise HTTPException(status_code=403, detail="Зөвхөн өөрийн хичээлээс оюутан хасна")

    enrollment = (
        db.query(models.ClassStudent)
        .filter(
            models.ClassStudent.organization_id == current_user.organization_id,
            models.ClassStudent.class_or_shift_id == class_id,
            models.ClassStudent.user_id == user_id,
        )
        .first()
    )
    if not enrollment:
        raise HTTPException(status_code=404, detail="Бүртгэл олдсонгүй")

    old_value = services.serialize_model_instance(enrollment, ["class_or_shift_id", "user_id"])
    db.delete(enrollment)
    log_audit(
        db,
        organization_id=current_user.organization_id,
        actor_user_id=current_user.id,
        action="remove_student",
        entity_type="class_student",
        entity_id=f"{class_id}:{user_id}",
        old_value=old_value,
        reason="student removed from class",
        request=request,
    )
    db.commit()
    return schemas.MessageResponse(message="Оюутныг хичээлээс хаслаа")


@app.get("/students/{user_id}/classes", response_model=list[schemas.ClassStudentOut])
def list_student_classes(
    user_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if current_user.role == "student" and current_user.id != user_id:
        raise HTTPException(status_code=403, detail="Зөвхөн өөрийн хичээлийг харна")

    return (
        db.query(models.ClassStudent)
        .filter(
            models.ClassStudent.organization_id == current_user.organization_id,
            models.ClassStudent.user_id == user_id,
        )
        .order_by(models.ClassStudent.created_at.desc())
        .all()
    )


# ---------------------------------------------------------------------------
# Sessions
# ---------------------------------------------------------------------------

@app.get("/sessions", response_model=list[schemas.SessionOut])
def list_sessions(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    return (
        db.query(models.AttendanceSession)
        .filter(models.AttendanceSession.organization_id == current_user.organization_id)
        .all()
    )


@app.post("/sessions", response_model=schemas.SessionOut)
def create_session(
    body: schemas.SessionCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin", "teacher")),
):
    ensure_same_org(current_user, body.organization_id)

    if db.query(models.AttendanceSession).filter(models.AttendanceSession.id == body.id).first():
        raise HTTPException(status_code=409, detail="Session ID давхардаж байна")

    session = models.AttendanceSession(**body.model_dump())
    db.add(session)
    db.commit()
    db.refresh(session)
    invalidate_dashboard_cache(current_user.organization_id)
    return session


@app.patch("/sessions/{session_id}", response_model=schemas.SessionOut)
def update_session(
    session_id: str,
    body: schemas.SessionUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin", "teacher")),
):
    session = (
        db.query(models.AttendanceSession)
        .filter(
            models.AttendanceSession.id == session_id,
            models.AttendanceSession.organization_id == current_user.organization_id,
        )
        .first()
    )
    if not session:
        raise HTTPException(status_code=404, detail="Session олдсонгүй")

    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(session, field, value)

    db.commit()
    db.refresh(session)
    invalidate_dashboard_cache(current_user.organization_id)
    return session

@app.get("/sessions/active-today", response_model=list[schemas.ActiveSessionOut])
def active_today_sessions(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    today = services.app_today()

    classes_query = db.query(models.ClassOrShift).filter(
        models.ClassOrShift.organization_id == current_user.organization_id,
        models.ClassOrShift.is_active == True,
    )

    if current_user.role == "teacher":
        classes_query = classes_query.filter(
            models.ClassOrShift.teacher_id == current_user.id
        )

    if current_user.role == "student":
        classes_query = (
            classes_query.join(
                models.ClassStudent,
                models.ClassStudent.class_or_shift_id == models.ClassOrShift.id,
            )
            .filter(models.ClassStudent.user_id == current_user.id)
        )

    classes = classes_query.all()

    result = []

    for cls in classes:
        if not is_class_scheduled_on_date(cls, today):
            continue

        if not cls.beacon_id or not cls.beacon:
            continue

        session = get_or_create_daily_session_for_class(db, cls, today)

        if not session.is_open:
            continue

        beacon = cls.beacon
        room_name = cls.room.name if cls.room else "-"

        result.append(
            schemas.ActiveSessionOut(
                session_id=session.id,
                class_or_shift_id=cls.id,
                class_name=cls.name,
                room_name=room_name,
                beacon_id=beacon.id,
                beacon_uuid=beacon.uuid,
                major=beacon.major,
                minor=beacon.minor,
                tx_power=beacon.tx_power,
                threshold_distance=beacon.threshold_distance or 3.0,
                session_date=session.session_date,
                start_time=session.start_time,
                end_time=session.end_time,
                is_open=session.is_open,
            )
        )

    db.commit()

    return result



def _is_daily_session_id(session_id: str) -> bool:
    parts = session_id.rsplit("_", 1)
    return len(parts) == 2 and len(parts[1]) == 8 and parts[1].isdigit()


def _candidate_daily_session_ids(session_id: str, target_date: date) -> list[str]:
    ids = [session_id]
    if not _is_daily_session_id(session_id):
        ids.append(f"{session_id}_{target_date.strftime('%Y%m%d')}")
    return ids


def _resolve_session_for_attendance(
    db: Session,
    *,
    organization_id: str,
    session_id: str,
    target_date: date,
) -> models.AttendanceSession:
    requested_session = (
        db.query(models.AttendanceSession)
        .filter(
            models.AttendanceSession.id == session_id,
            models.AttendanceSession.organization_id == organization_id,
        )
        .first()
    )

    if not requested_session:
        raise HTTPException(status_code=404, detail="Session олдсонгүй")

    if not requested_session.is_open:
        raise HTTPException(status_code=400, detail="Session хаагдсан байна")

    # /sessions/active-today endpoint аль хэдийн CLASS001_YYYYMMDD хэлбэрийн
    # өдөр тутмын session_id буцаадаг. Тийм үед дахиж _YYYYMMDD залгахгүй.
    if _is_daily_session_id(requested_session.id):
        if requested_session.session_date and requested_session.session_date != target_date:
            raise HTTPException(status_code=400, detail="Session огноо өнөөдрийнх биш байна")
        return requested_session

    daily_session_id = f"{requested_session.id}_{target_date.strftime('%Y%m%d')}"

    daily_session = (
        db.query(models.AttendanceSession)
        .filter(
            models.AttendanceSession.id == daily_session_id,
            models.AttendanceSession.organization_id == organization_id,
        )
        .first()
    )

    if daily_session:
        if not daily_session.is_open:
            raise HTTPException(status_code=400, detail="Session хаагдсан байна")
        return daily_session

    daily_session = models.AttendanceSession(
        id=daily_session_id,
        organization_id=requested_session.organization_id,
        class_or_shift_id=requested_session.class_or_shift_id,
        beacon_id=requested_session.beacon_id,
        session_date=target_date,
        start_time=requested_session.start_time,
        end_time=requested_session.end_time,
        is_open=True,
    )
    db.add(daily_session)
    db.flush()
    return daily_session

# ---------------------------------------------------------------------------
# Attendance
# ---------------------------------------------------------------------------

@app.post("/attendance/check", response_model=schemas.AttendanceOut)
async def attendance_check(
    request: Request,
    body: schemas.AttendanceRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    check_rate_limit(request)

    ensure_attendance_allowed(current_user)

    if body.user_id != current_user.id:
        raise HTTPException(
            status_code=403,
            detail="user_id token хэрэглэгчтэй таарахгүй байна",
        )

    services.ensure_nonce_is_valid(
        db,
        organization_id=current_user.organization_id,
        user_id=current_user.id,
        nonce=body.nonce,
        client_timestamp=body.client_timestamp,
    )

    check_in_at = services.app_now_naive()
    today = check_in_at.date()

    session = _resolve_session_for_attendance(
        db,
        organization_id=current_user.organization_id,
        session_id=body.session_id,
        target_date=today,
    )
    class_shift = session.class_or_shift

    if not class_shift or not class_shift.is_active:
        raise HTTPException(status_code=400, detail="Хичээл/ээлж идэвхгүй байна")

    # Student зөвхөн өөрийн бүртгэлтэй хичээл/ээлж дээр check-in хийж чадна.
    ensure_student_enrolled(db, current_user, session.class_or_shift_id)

    # Session цагийн хүрээнд байгаа эсэхийг backend дээр заавал шалгана.
    ensure_session_time_allowed(session, check_in_at)

    device = get_registered_active_device(
        db,
        user_id=current_user.id,
        device_uuid=body.device_uuid,
    )

    beacon = find_active_beacon_for_attendance(
        db,
        organization_id=current_user.organization_id,
        beacon_uuid=body.beacon_uuid,
        major=body.major,
        minor=body.minor,
    )

    # App-ээс ирсэн distance утгыг зөвхөн UI-д найдахгүй, backend дээр threshold-тэй шалгана.
    ensure_distance_allowed(beacon, body.distance)
    ensure_ble_signal_quality(body)

    if session.beacon_id and beacon.id != session.beacon_id:
        raise HTTPException(
            status_code=400,
            detail="Энэ session-д таарах beacon биш байна",
        )

    # ------------------------------------------------------------
    # 5. Нэг хэрэглэгч тухайн өдрийн session дээр зөвхөн нэг check-in хийнэ.
    # ------------------------------------------------------------
    existing = (
        db.query(models.Attendance)
        .filter(
            models.Attendance.session_id == session.id,
            models.Attendance.user_id == current_user.id,
        )
        .first()
    )
    if existing:
        raise HTTPException(status_code=409, detail="Ирц аль хэдийн бүртгэгдсэн байна")

    if body.rssi_samples and services.detect_suspicious_rssi(body.rssi_samples):
        raise HTTPException(
            status_code=400,
            detail="RSSI хэт тогтвортой — хуурамч дохио байж болзошгүй",
        )

    # Duplicate cache-г бүх validation амжилттай болсны дараа шалгана.
    # Ингэснээр validation fail болсон оролдлого 5 минутын cache lock үүсгэхгүй.
    cache_key = f"att:{current_user.id}:{session.id}"
    if redis_client.exists(cache_key):
        raise HTTPException(status_code=400, detail="Duplicate check-in (cache)")

    late_minutes = 0

    if class_shift and class_shift.start_time:
        threshold_minutes = class_shift.late_after_minutes or 10

        # Өнөөдрийн session тул өнөөдрийн огноогоор late minutes тооцно.
        scheduled_start = datetime.combine(today, class_shift.start_time)
        diff_minutes = (check_in_at - scheduled_start).total_seconds() / 60

        if diff_minutes > threshold_minutes:
            late_minutes = int(diff_minutes - threshold_minutes)

    status = "late" if late_minutes > 0 else "present"

    rssi_variance = (
        services.compute_rssi_variance(body.rssi_samples)
        if body.rssi_samples
        else None
    )

    attendance = models.Attendance(
        organization_id=current_user.organization_id,

        # Гол өөрчлөлт:
        # SESSION002 биш, SESSION002_YYYYMMDD дээр хадгална.
        session_id=session.id,

        user_id=current_user.id,
        device_id=device.id,
        beacon_id=beacon.id,

        # History / Report filter-д бодит check-in хийсэн огноог ашиглана.
        attendance_date=today,

        check_in_time=check_in_at,
        distance_m=body.distance,
        rssi=body.rssi,
        rssi_variance=rssi_variance,
        status=status,
        detection_method="ble",
        late_minutes=late_minutes,
        note=body.note,
    )

    db.add(attendance)
    device.last_seen_at = check_in_at
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Ирц аль хэдийн бүртгэгдсэн байна")

    db.refresh(attendance)
    redis_client.setex(cache_key, 300, "checked")

    invalidate_dashboard_cache(current_user.organization_id)

    await manager.broadcast(
        current_user.organization_id,
        {
            "type": "attendance_check_in",
            "payload": {
                "user_id": current_user.id,
                "session_id": session.id,
                "status": status,
                "beacon_id": beacon.id,
            },
        },
    )

    return attendance


@app.post("/attendance/checkout", response_model=schemas.AttendanceOut)
async def attendance_checkout(
    request: Request,
    body: schemas.AttendanceCheckoutRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    check_rate_limit(request)

    ensure_attendance_allowed(current_user)

    services.ensure_nonce_is_valid(
        db,
        organization_id=current_user.organization_id,
        user_id=current_user.id,
        nonce=body.nonce,
        client_timestamp=body.client_timestamp,
    )

    checkout_at = services.app_now_naive()
    candidate_session_ids = _candidate_daily_session_ids(body.session_id, checkout_at.date())

    attendance = (
        db.query(models.Attendance)
        .filter(
            models.Attendance.organization_id == current_user.organization_id,
            models.Attendance.session_id.in_(candidate_session_ids),
            models.Attendance.user_id == current_user.id,
        )
        .order_by(models.Attendance.check_in_time.desc())
        .first()
    )
    if not attendance:
        raise HTTPException(status_code=404, detail="Ирцийн бичлэг олдсонгүй")
    if attendance.check_out_time:
        raise HTTPException(status_code=409, detail="Check-out аль хэдийн бүртгэгдсэн байна")

    if attendance.session and not attendance.session.is_open:
        raise HTTPException(status_code=400, detail="Session хаагдсан байна")

    if attendance.device:
        current_device = get_registered_active_device(
            db,
            user_id=current_user.id,
            device_uuid=body.device_uuid,
        )
        if current_device.id != attendance.device_id:
            raise HTTPException(status_code=403, detail="Check-out төхөөрөмж таарахгүй байна")

    attendance.check_out_time = checkout_at
    attendance.status = "checked_out"
    if body.note:
        attendance.note = body.note

    db.commit()
    db.refresh(attendance)

    invalidate_dashboard_cache(current_user.organization_id)

    await manager.broadcast(
        current_user.organization_id,
        {
            "type": "attendance_check_out",
            "payload": {
                "user_id": current_user.id,
                # Бодитоор DB-д хадгалагдсан daily session id-г буцаана.
                "session_id": attendance.session_id,
                "status": attendance.status,
            },
        },
    )

    return attendance


def _template_session_id(session_id: str) -> str:
    parts = session_id.split("_")
    if len(parts) >= 2 and parts[-1].isdigit() and len(parts[-1]) == 8:
        return "_".join(parts[:-1])
    return session_id


def _get_or_create_daily_session(
    db: Session,
    *,
    organization_id: str,
    template_session_id: str,
    actual_date: date,
) -> models.AttendanceSession:
    template_session = (
        db.query(models.AttendanceSession)
        .filter(
            models.AttendanceSession.id == template_session_id,
            models.AttendanceSession.organization_id == organization_id,
        )
        .first()
    )
    if not template_session:
        raise HTTPException(status_code=404, detail="Session олдсонгүй")
    if not template_session.is_open:
        raise HTTPException(status_code=400, detail="Session хаагдсан байна")

    today_key = actual_date.strftime("%Y%m%d")
    daily_session_id = f"{template_session.id}_{today_key}"

    daily_session = (
        db.query(models.AttendanceSession)
        .filter(
            models.AttendanceSession.id == daily_session_id,
            models.AttendanceSession.organization_id == organization_id,
        )
        .first()
    )
    if daily_session:
        return daily_session

    daily_session = models.AttendanceSession(
        id=daily_session_id,
        organization_id=template_session.organization_id,
        class_or_shift_id=template_session.class_or_shift_id,
        beacon_id=template_session.beacon_id,
        session_date=actual_date,
        start_time=template_session.start_time,
        end_time=template_session.end_time,
        is_open=True,
    )
    db.add(daily_session)
    db.flush()
    return daily_session


@app.post("/attendance/sync", response_model=schemas.AttendanceOut)
async def attendance_sync(
    request: Request,
    body: schemas.AttendanceSyncRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    check_rate_limit(request)
    ensure_attendance_allowed(current_user)

    services.ensure_nonce_is_valid(
        db,
        organization_id=current_user.organization_id,
        user_id=current_user.id,
        nonce=body.nonce,
        client_timestamp=body.sync_timestamp,
    )

    actual_at = services.to_app_naive(body.detected_at)
    actual_date = actual_at.date()
    payload = dict(body.payload or {})
    sync_type = body.type

    if sync_type == "check_in":
        # Payload structure-г existing AttendanceRequest schema-гаар validate хийнэ.
        payload["client_timestamp"] = body.sync_timestamp
        payload["nonce"] = body.nonce
        check_body = schemas.AttendanceRequest(**payload)

        if check_body.user_id != current_user.id:
            raise HTTPException(
                status_code=403,
                detail="user_id token хэрэглэгчтэй таарахгүй байна",
            )

        session = _resolve_session_for_attendance(
            db,
            organization_id=current_user.organization_id,
            session_id=check_body.session_id,
            target_date=actual_date,
        )
        class_shift = session.class_or_shift
        if not class_shift or not class_shift.is_active:
            raise HTTPException(status_code=400, detail="Хичээл/ээлж идэвхгүй байна")

        ensure_student_enrolled(db, current_user, session.class_or_shift_id)
        ensure_session_time_allowed(session, actual_at)

        device = get_registered_active_device(
            db,
            user_id=current_user.id,
            device_uuid=check_body.device_uuid,
        )

        beacon = find_active_beacon_for_attendance(
            db,
            organization_id=current_user.organization_id,
            beacon_uuid=check_body.beacon_uuid,
            major=check_body.major,
            minor=check_body.minor,
        )

        ensure_distance_allowed(beacon, check_body.distance)
        ensure_ble_signal_quality(check_body)

        if session.beacon_id and beacon.id != session.beacon_id:
            raise HTTPException(
                status_code=400,
                detail="Энэ session-д таарах beacon биш байна",
            )

        existing = (
            db.query(models.Attendance)
            .filter(
                models.Attendance.session_id == session.id,
                models.Attendance.user_id == current_user.id,
            )
            .first()
        )
        if existing:
            return existing

        if check_body.rssi_samples and services.detect_suspicious_rssi(check_body.rssi_samples):
            raise HTTPException(
                status_code=400,
                detail="RSSI хэт тогтвортой — хуурамч дохио байж болзошгүй",
            )

        late_minutes = 0
        if class_shift and class_shift.start_time:
            threshold_minutes = class_shift.late_after_minutes or 10
            scheduled_start = datetime.combine(actual_date, class_shift.start_time)
            diff_minutes = (actual_at - scheduled_start).total_seconds() / 60
            if diff_minutes > threshold_minutes:
                late_minutes = int(diff_minutes - threshold_minutes)

        status = "late" if late_minutes > 0 else "present"
        rssi_variance = (
            services.compute_rssi_variance(check_body.rssi_samples)
            if check_body.rssi_samples
            else None
        )

        attendance = models.Attendance(
            organization_id=current_user.organization_id,
            session_id=session.id,
            user_id=current_user.id,
            device_id=device.id,
            beacon_id=beacon.id,
            attendance_date=actual_date,
            check_in_time=actual_at,
            distance_m=check_body.distance,
            rssi=check_body.rssi,
            rssi_variance=rssi_variance,
            status=status,
            detection_method="ble_offline_sync",
            late_minutes=late_minutes,
            note=check_body.note,
        )

        db.add(attendance)
        device.last_seen_at = actual_at
        db.commit()
        db.refresh(attendance)
        invalidate_dashboard_cache(current_user.organization_id)

        await manager.broadcast(
            current_user.organization_id,
            {
                "type": "attendance_check_in",
                "payload": {
                    "user_id": current_user.id,
                    "session_id": session.id,
                    "status": status,
                    "beacon_id": beacon.id,
                    "synced": True,
                },
            },
        )
        return attendance

    if sync_type == "check_out":
        payload["client_timestamp"] = body.sync_timestamp
        payload["nonce"] = body.nonce
        checkout_body = schemas.AttendanceCheckoutRequest(**payload)

        candidate_session_ids = _candidate_daily_session_ids(checkout_body.session_id, actual_date)

        attendance = (
            db.query(models.Attendance)
            .filter(
                models.Attendance.organization_id == current_user.organization_id,
                models.Attendance.session_id.in_(candidate_session_ids),
                models.Attendance.user_id == current_user.id,
            )
            .order_by(models.Attendance.check_in_time.desc())
            .first()
        )
        if not attendance:
            raise HTTPException(status_code=404, detail="Ирцийн бичлэг олдсонгүй")
        if attendance.check_out_time:
            return attendance

        if attendance.session and not attendance.session.is_open:
            raise HTTPException(status_code=400, detail="Session хаагдсан байна")

        if attendance.device:
            current_device = get_registered_active_device(
                db,
                user_id=current_user.id,
                device_uuid=checkout_body.device_uuid,
            )
            if current_device.id != attendance.device_id:
                raise HTTPException(status_code=403, detail="Check-out төхөөрөмж таарахгүй байна")

        attendance.check_out_time = actual_at
        attendance.status = "checked_out"
        if checkout_body.note:
            attendance.note = checkout_body.note

        db.commit()
        db.refresh(attendance)
        invalidate_dashboard_cache(current_user.organization_id)

        await manager.broadcast(
            current_user.organization_id,
            {
                "type": "attendance_check_out",
                "payload": {
                    "user_id": current_user.id,
                    "session_id": attendance.session_id,
                    "status": attendance.status,
                    "synced": True,
                },
            },
        )
        return attendance

    raise HTTPException(status_code=400, detail="sync type буруу байна")


@app.get("/attendance/all", response_model=list[schemas.AttendanceOut])
def get_all_attendance(
    session_id: Optional[str] = None,
    class_id: Optional[str] = None,
    user_id: Optional[str] = None,
    status: Optional[str] = None,
    from_date: Optional[date] = None,
    to_date: Optional[date] = None,
    limit: int = 500,
    offset: int = 0,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin", "teacher")),
):
    query = attendance_scope_query(db, current_user.organization_id)
    query = restrict_teacher_attendance_query(query, current_user)

    query = apply_attendance_filters(
        query,
        class_id=class_id,
        session_id=session_id,
        user_id=user_id,
        status=status,
        from_date=from_date,
        to_date=to_date,
    )

    return (
        query.order_by(models.Attendance.check_in_time.desc())
        .offset(max(offset, 0))
        .limit(min(max(limit, 1), 1000))
        .all()
    )


@app.get("/attendance/history/{user_id}", response_model=list[schemas.AttendanceOut])
def get_attendance_history(
    user_id: str,
    from_date: Optional[date] = None,
    to_date: Optional[date] = None,
    status: Optional[str] = None,
    session_id: Optional[str] = None,
    class_id: Optional[str] = None,
    limit: int = 300,
    offset: int = 0,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if current_user.role not in ("admin", "teacher") and current_user.id != user_id:
        raise HTTPException(status_code=403, detail="Хандах эрх байхгүй")

    query = attendance_scope_query(db, current_user.organization_id)
    query = restrict_teacher_attendance_query(query, current_user)
    query = apply_attendance_filters(
        query,
        class_id=class_id,
        session_id=session_id,
        user_id=user_id,
        status=status,
        from_date=from_date,
        to_date=to_date,
    )

    return (
        query.order_by(models.Attendance.check_in_time.desc())
        .offset(max(offset, 0))
        .limit(min(max(limit, 1), 1000))
        .all()
    )


@app.patch("/attendance/{attendance_id}/manual-update", response_model=schemas.AttendanceOut)
def manual_update_attendance(
    attendance_id: int,
    body: schemas.ManualAttendanceUpdateRequest,
    request: Request,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin", "teacher")),
):
    attendance = (
        db.query(models.Attendance)
        .filter(
            models.Attendance.id == attendance_id,
            models.Attendance.organization_id == current_user.organization_id,
        )
        .first()
    )
    if not attendance:
        raise HTTPException(status_code=404, detail="Ирцийн бичлэг олдсонгүй")

    old_value = services.serialize_model_instance(
        attendance,
        ["status", "note", "check_in_time", "check_out_time"],
    )

    if body.status:
        attendance.status = body.status
    if body.note is not None:
        attendance.note = body.note
    if body.check_in_time:
        attendance.check_in_time = body.check_in_time
    if body.check_out_time:
        attendance.check_out_time = body.check_out_time

    new_value = services.serialize_model_instance(
        attendance,
        ["status", "note", "check_in_time", "check_out_time"],
    )

    log = models.AuditLog(
        organization_id=current_user.organization_id,
        actor_user_id=current_user.id,
        action="manual_update",
        entity_type="attendance",
        entity_id=str(attendance_id),
        old_value=old_value,
        new_value=new_value,
        reason=body.reason,
        ip_address=request.client.host if request.client else None,
    )
    db.add(log)
    db.commit()
    db.refresh(attendance)

    invalidate_dashboard_cache(current_user.organization_id)

    return attendance
# ---------------------------------------------------------------------------
# Attendance appeals / requests
# ---------------------------------------------------------------------------

@app.post("/attendance/appeals", response_model=schemas.AttendanceAppealOut)
def create_attendance_appeal(
    body: schemas.AttendanceAppealCreate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("student", "teacher")),
):
    session = (
        db.query(models.AttendanceSession)
        .filter(
            models.AttendanceSession.id == body.session_id,
            models.AttendanceSession.organization_id == current_user.organization_id,
        )
        .first()
    )
    if not session:
        raise HTTPException(status_code=404, detail="Session олдсонгүй")

    attendance = None
    if body.attendance_id is not None:
        attendance = (
            db.query(models.Attendance)
            .filter(
                models.Attendance.id == body.attendance_id,
                models.Attendance.organization_id == current_user.organization_id,
            )
            .first()
        )
        if not attendance:
            raise HTTPException(status_code=404, detail="Ирцийн бичлэг олдсонгүй")

        if current_user.role == "student" and attendance.user_id != current_user.id:
            raise HTTPException(status_code=403, detail="Зөвхөн өөрийн ирц дээр хүсэлт гаргана")

    appeal = models.AttendanceAppeal(
        organization_id=current_user.organization_id,
        attendance_id=body.attendance_id,
        user_id=current_user.id,
        session_id=body.session_id,
        reason_type=body.reason_type,
        message=body.message,
        status="pending",
    )
    db.add(appeal)
    db.flush()

    log_audit(
        db,
        organization_id=current_user.organization_id,
        actor_user_id=current_user.id,
        action="create_attendance_appeal",
        entity_type="attendance_appeal",
        entity_id=str(appeal.id),
        new_value=services.serialize_model_instance(
            appeal,
            ["attendance_id", "user_id", "session_id", "reason_type", "message", "status"],
        ),
        reason="attendance appeal created",
        request=request,
    )

    db.commit()
    db.refresh(appeal)
    return appeal


@app.get("/attendance/appeals", response_model=list[schemas.AttendanceAppealOut])
def list_attendance_appeals(
    status: Optional[str] = None,
    user_id: Optional[str] = None,
    session_id: Optional[str] = None,
    limit: int = 300,
    offset: int = 0,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    query = db.query(models.AttendanceAppeal).filter(
        models.AttendanceAppeal.organization_id == current_user.organization_id
    )

    if current_user.role == "student":
        query = query.filter(models.AttendanceAppeal.user_id == current_user.id)
    elif current_user.role == "teacher":
        # Багш өөрийн хичээл/session-тэй холбоотой appeal-уудыг харна
        query = (
            query.join(
                models.AttendanceSession,
                models.AttendanceAppeal.session_id == models.AttendanceSession.id,
            )
            .join(
                models.ClassOrShift,
                models.AttendanceSession.class_or_shift_id == models.ClassOrShift.id,
            )
            .filter(models.ClassOrShift.teacher_id == current_user.id)
        )
    elif current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Хандах эрх байхгүй")

    if status:
        query = query.filter(models.AttendanceAppeal.status == status)
    if user_id:
        query = query.filter(models.AttendanceAppeal.user_id == user_id)
    if session_id:
        query = query.filter(models.AttendanceAppeal.session_id == session_id)

    return (
        query.order_by(models.AttendanceAppeal.created_at.desc())
        .offset(max(offset, 0))
        .limit(min(max(limit, 1), 1000))
        .all()
    )


@app.patch("/attendance/appeals/{appeal_id}/review", response_model=schemas.AttendanceAppealOut)
def review_attendance_appeal(
    appeal_id: int,
    body: schemas.AttendanceAppealReview,
    request: Request,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin", "teacher")),
):
    appeal = (
        db.query(models.AttendanceAppeal)
        .filter(
            models.AttendanceAppeal.id == appeal_id,
            models.AttendanceAppeal.organization_id == current_user.organization_id,
        )
        .first()
    )
    if not appeal:
        raise HTTPException(status_code=404, detail="Appeal олдсонгүй")

    if current_user.role == "teacher":
        session = (
            db.query(models.AttendanceSession)
            .join(models.ClassOrShift)
            .filter(
                models.AttendanceSession.id == appeal.session_id,
                models.AttendanceSession.organization_id == current_user.organization_id,
                models.ClassOrShift.teacher_id == current_user.id,
            )
            .first()
        )
        if not session:
            raise HTTPException(status_code=403, detail="Зөвхөн өөрийн session-ийн хүсэлтийг review хийнэ")

    if body.status not in ("approved", "rejected"):
        raise HTTPException(status_code=400, detail="status нь approved эсвэл rejected байна")

    old_value = services.serialize_model_instance(
        appeal,
        ["status", "reviewed_by", "review_note", "reviewed_at"],
    )

    appeal.status = body.status
    appeal.reviewed_by = current_user.id
    appeal.review_note = body.review_note
    appeal.reviewed_at = services.utcnow_naive()

    # Approve үед attendance засах боломж
    if body.status == "approved" and appeal.attendance_id is not None:
        attendance = (
            db.query(models.Attendance)
            .filter(
                models.Attendance.id == appeal.attendance_id,
                models.Attendance.organization_id == current_user.organization_id,
            )
            .first()
        )
        if attendance:
            old_att = services.serialize_model_instance(
                attendance,
                ["status", "note", "check_in_time", "check_out_time", "late_minutes"],
            )

            if body.correction_status:
                attendance.status = body.correction_status
            if body.correction_note is not None:
                attendance.note = body.correction_note
            if body.correction_check_in_time:
                attendance.check_in_time = body.correction_check_in_time
            if body.correction_check_out_time:
                attendance.check_out_time = body.correction_check_out_time
            if body.correction_late_minutes is not None:
                attendance.late_minutes = body.correction_late_minutes

            new_att = services.serialize_model_instance(
                attendance,
                ["status", "note", "check_in_time", "check_out_time", "late_minutes"],
            )

            log_audit(
                db,
                organization_id=current_user.organization_id,
                actor_user_id=current_user.id,
                action="appeal_approved_attendance_corrected",
                entity_type="attendance",
                entity_id=str(attendance.id),
                old_value=old_att,
                new_value=new_att,
                reason=body.review_note,
                request=request,
            )

    new_value = services.serialize_model_instance(
        appeal,
        ["status", "reviewed_by", "review_note", "reviewed_at"],
    )

    log_audit(
        db,
        organization_id=current_user.organization_id,
        actor_user_id=current_user.id,
        action="review_attendance_appeal",
        entity_type="attendance_appeal",
        entity_id=str(appeal.id),
        old_value=old_value,
        new_value=new_value,
        reason=body.review_note,
        request=request,
    )

    db.commit()
    db.refresh(appeal)
    invalidate_dashboard_cache(current_user.organization_id)
    return appeal


# ---------------------------------------------------------------------------
# Teacher session summary
# ---------------------------------------------------------------------------

@app.get(
    "/dashboard/teacher/summary",
    response_model=schemas.TeacherSessionSummaryResponse,
)
def teacher_session_summary(
    target_date: Optional[date] = None,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("teacher", "admin")),
):
    selected_date = target_date or services.app_today()

    session_query = (
        db.query(models.AttendanceSession)
        .join(
            models.ClassOrShift,
            models.AttendanceSession.class_or_shift_id == models.ClassOrShift.id,
        )
        .filter(
            models.AttendanceSession.organization_id == current_user.organization_id,
            models.AttendanceSession.session_date == selected_date,
        )
    )

    # Teacher зөвхөн өөрийн session-үүдийг харна
    if current_user.role == "teacher":
        session_query = session_query.filter(
            models.ClassOrShift.teacher_id == current_user.id
        )

    sessions = (
        session_query
        .order_by(models.AttendanceSession.start_time.asc())
        .all()
    )

    items = []

    for s in sessions:
        cls = s.class_or_shift

        # Class-д бүртгэлтэй оюутны тоо
        total_students = (
            db.query(models.ClassStudent)
            .filter(
                models.ClassStudent.organization_id == current_user.organization_id,
                models.ClassStudent.class_or_shift_id == s.class_or_shift_id,
            )
            .count()
        )

        # Багш өөрөө BLE check-in хийдэг болсон тул багшийг нийт тоонд оруулна.
        teacher_count = 1 if cls and cls.teacher_id else 0

        # Нийт оролцогч = оюутнууд + тухайн session-ийн багш
        total_people = total_students + teacher_count

        records = (
            db.query(models.Attendance)
            .join(models.User, models.Attendance.user_id == models.User.id)
            .filter(
                models.Attendance.organization_id == current_user.organization_id,
                models.Attendance.session_id == s.id,
                models.User.role.in_(["student", "teacher"]),
            )
            .all()
        )

        # Давхар check-in байвал нэг user-г нэг удаа л тооцно
        present_user_ids = {
            r.user_id
            for r in records
            if r.status == "present"
        }

        late_user_ids = {
            r.user_id
            for r in records
            if r.status == "late"
        }

        checked_out_user_ids = {
            r.user_id
            for r in records
            if r.check_out_time is not None or r.status == "checked_out"
        }

        attended_user_ids = {
            r.user_id
            for r in records
            if r.status in ("present", "late", "checked_out")
        }

        present = len(present_user_ids)
        late = len(late_user_ids)
        checked_out = len(checked_out_user_ids)
        attended = len(attended_user_ids)

        absent = max(total_people - attended, 0)

        # 200% гарахаас хамгаална
        if total_people == 0:
            attendance_rate = 0.0
        else:
            attendance_rate = round((attended / total_people) * 100, 1)
            attendance_rate = min(attendance_rate, 100.0)

        room_name = "-"
        if cls and cls.room:
            room_name = cls.room.name

        items.append(
            schemas.TeacherSessionSummaryItem(
                session_id=s.id,
                class_or_shift_id=s.class_or_shift_id,
                class_name=cls.name if cls else "-",
                room_name=room_name,
                session_date=str(s.session_date),
                start_time=str(s.start_time) if s.start_time else None,
                end_time=str(s.end_time) if s.end_time else None,
                is_open=s.is_open,

                # Нэр нь total_students хэвээр байгаа ч утга нь student + teacher
                total_students=total_people,

                present=present,
                late=late,
                checked_out=checked_out,
                absent=absent,
                attendance_rate=attendance_rate,
            )
        )

    return schemas.TeacherSessionSummaryResponse(
        teacher_id=current_user.id,
        today=str(selected_date),
        sessions=items,
    )
# ---------------------------------------------------------------------------
# Dashboard analytics
# ---------------------------------------------------------------------------

@app.get("/dashboard/overview")
def dashboard_overview(
    month: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin", "teacher")),
):
    from sqlalchemy import extract

    month_key = month or "all"
    scope_key = current_user.id if current_user.role == "teacher" else "all"
    cache_key = f"dashboard:{current_user.organization_id}:{current_user.role}:{scope_key}:{month_key}"

    cached = redis_client.get(cache_key)
    if cached:
        return json.loads(cached)

    query = attendance_scope_query(db, current_user.organization_id)
    query = restrict_teacher_attendance_query(query, current_user)

    if month:
        try:
            year_s, month_s = month.split("-")
            year, mon = int(year_s), int(month_s)
        except ValueError:
            raise HTTPException(status_code=400, detail="month формат буруу байна (YYYY-MM)")

        query = query.filter(
            extract("year", models.Attendance.attendance_date) == year,
            extract("month", models.Attendance.attendance_date) == mon,
        )

    open_sessions_query = db.query(models.AttendanceSession).filter(
        models.AttendanceSession.organization_id == current_user.organization_id,
        models.AttendanceSession.is_open == True,
    )
    open_sessions_query = restrict_teacher_session_query(open_sessions_query, current_user)

    result = {
        "month": month,
        "total_attendance": query.count(),
        "total_present": query.filter(models.Attendance.status == "present").count(),
        "total_late": query.filter(models.Attendance.status == "late").count(),
        "open_sessions": open_sessions_query.count(),
    }

    redis_client.setex(cache_key, 60, json.dumps(result))
    return result


@app.get("/dashboard/daily-trend")
def dashboard_daily_trend(
    month: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin", "teacher")),
):
    from sqlalchemy import extract, func

    try:
        year_s, month_s = month.split("-")
        year, mon = int(year_s), int(month_s)
    except ValueError:
        raise HTTPException(status_code=400, detail="month формат буруу байна (YYYY-MM)")

    query = attendance_scope_query(db, current_user.organization_id).filter(
        extract("year", models.Attendance.attendance_date) == year,
        extract("month", models.Attendance.attendance_date) == mon,
    )
    query = restrict_teacher_attendance_query(query, current_user)

    rows = (
        query.with_entities(
            models.Attendance.attendance_date.label("attendance_date"),
            func.count(models.Attendance.id).label("count"),
        )
        .group_by(models.Attendance.attendance_date)
        .order_by(models.Attendance.attendance_date.asc())
        .all()
    )

    return {
        "month": month,
        "items": [{"date": str(r.attendance_date), "count": r.count} for r in rows],
    }


@app.get("/dashboard/session-summary")
def dashboard_session_summary(
    month: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin", "teacher")),
):
    from sqlalchemy import case, extract, func

    try:
        year_s, month_s = month.split("-")
        year, mon = int(year_s), int(month_s)
    except ValueError:
        raise HTTPException(status_code=400, detail="month формат буруу байна (YYYY-MM)")

    query = attendance_scope_query(db, current_user.organization_id).filter(
        extract("year", models.Attendance.attendance_date) == year,
        extract("month", models.Attendance.attendance_date) == mon,
    )
    query = restrict_teacher_attendance_query(query, current_user)

    rows = (
        query.with_entities(
            models.Attendance.session_id.label("session_id"),
            func.count(models.Attendance.id).label("total"),
            func.sum(case((models.Attendance.status == "present", 1), else_=0)).label("present"),
            func.sum(case((models.Attendance.status == "late", 1), else_=0)).label("late"),
            func.sum(case((models.Attendance.check_out_time != None, 1), else_=0)).label("checked_out"),
        )
        .group_by(models.Attendance.session_id)
        .order_by(func.count(models.Attendance.id).desc())
        .all()
    )

    return {
        "month": month,
        "items": [
            {
                "session_id": r.session_id,
                "total": int(r.total or 0),
                "present": int(r.present or 0),
                "late": int(r.late or 0),
                "checked_out": int(r.checked_out or 0),
            }
            for r in rows
        ],
    }


@app.get("/dashboard/late-ranking")
def dashboard_late_ranking(
    month: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin", "teacher")),
):
    from sqlalchemy import extract, func

    try:
        year_s, month_s = month.split("-")
        year, mon = int(year_s), int(month_s)
    except ValueError:
        raise HTTPException(status_code=400, detail="month формат буруу байна (YYYY-MM)")

    query = attendance_scope_query(db, current_user.organization_id).filter(
        models.Attendance.status == "late",
        extract("year", models.Attendance.attendance_date) == year,
        extract("month", models.Attendance.attendance_date) == mon,
    )
    query = restrict_teacher_attendance_query(query, current_user)

    rows = (
        query.with_entities(
            models.Attendance.user_id.label("user_id"),
            func.count(models.Attendance.id).label("late_count"),
            func.sum(models.Attendance.late_minutes).label("late_minutes_sum"),
        )
        .group_by(models.Attendance.user_id)
        .order_by(func.sum(models.Attendance.late_minutes).desc())
        .limit(10)
        .all()
    )

    return {
        "month": month,
        "items": [
            {
                "user_id": r.user_id,
                "late_count": int(r.late_count or 0),
                "late_minutes_sum": int(r.late_minutes_sum or 0),
            }
            for r in rows
        ],
    }


# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------

def normalize_report_scope_for_role(
    current_user: models.User,
    *,
    class_id: Optional[str] = None,
    session_id: Optional[str] = None,
    user_id: Optional[str] = None,
):
    """
    Report эрхийн дүрэм:
    - admin: бүх report харж болно
    - teacher: байгууллагын report харж болно
    - student: зөвхөн өөрийн user_id report харна
    """
    if current_user.role == "student":
        return class_id, session_id, current_user.id

    if current_user.role in ("admin", "teacher"):
        return class_id, session_id, user_id

    raise HTTPException(status_code=403, detail="Report харах эрхгүй байна")


def report_records_query(
    db: Session,
    *,
    organization_id: str,
    month: str,
    class_id: Optional[str] = None,
    session_id: Optional[str] = None,
    user_id: Optional[str] = None,
    status: Optional[str] = None,
):
    from sqlalchemy import extract

    year, mon = parse_month(month)

    query = attendance_scope_query(db, organization_id).filter(
        extract("year", models.Attendance.attendance_date) == year,
        extract("month", models.Attendance.attendance_date) == mon,
    )

    return apply_attendance_filters(
        query,
        class_id=class_id,
        session_id=session_id,
        user_id=user_id,
        status=status,
    )


@app.get("/report/summary/{month}")
def report_summary(
    month: str,
    class_id: Optional[str] = None,
    session_id: Optional[str] = None,
    user_id: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    from sqlalchemy import func

    class_id, session_id, user_id = normalize_report_scope_for_role(
        current_user,
        class_id=class_id,
        session_id=session_id,
        user_id=user_id,
    )

    query = report_records_query(
        db,
        organization_id=current_user.organization_id,
        month=month,
        class_id=class_id,
        session_id=session_id,
        user_id=user_id,
    )

    rows = (
        query.with_entities(
            models.Attendance.status,
            func.count(models.Attendance.id).label("count"),
        )
        .group_by(models.Attendance.status)
        .all()
    )

    summary = [
        {
            "status": r.status,
            "count": int(r.count or 0),
        }
        for r in rows
    ]

    return {
        "month": month,
        "summary": summary,
    }


@app.get("/report/monthly/{month}")
def report_monthly(
    month: str,
    class_id: Optional[str] = None,
    session_id: Optional[str] = None,
    user_id: Optional[str] = None,
    status: Optional[str] = None,
    limit: int = 1000,
    offset: int = 0,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    class_id, session_id, user_id = normalize_report_scope_for_role(
        current_user,
        class_id=class_id,
        session_id=session_id,
        user_id=user_id,
    )

    query = report_records_query(
        db,
        organization_id=current_user.organization_id,
        month=month,
        class_id=class_id,
        session_id=session_id,
        user_id=user_id,
        status=status,
    )

    records = (
        query.order_by(
            models.Attendance.attendance_date.desc(),
            models.Attendance.check_in_time.desc(),
        )
        .offset(max(offset, 0))
        .limit(min(max(limit, 1), 2000))
        .all()
    )

    data = [
        {
            "id": r.id,
            "user_id": r.user_id,
            "session_id": r.session_id,
            "date": str(r.attendance_date),
            "check_in": str(r.check_in_time),
            "check_out": str(r.check_out_time) if r.check_out_time else None,
            "status": r.status,
            "late_minutes": r.late_minutes,
            "rssi": r.rssi,
            "distance_m": r.distance_m,
        }
        for r in records
    ]

    return {
        "month": month,
        "total": len(data),
        "records": data,
    }


@app.get("/report/excel/{month}")
def report_excel(
    month: str,
    class_id: Optional[str] = None,
    session_id: Optional[str] = None,
    user_id: Optional[str] = None,
    status: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    class_id, session_id, user_id = normalize_report_scope_for_role(
        current_user,
        class_id=class_id,
        session_id=session_id,
        user_id=user_id,
    )

    records = (
        report_records_query(
            db,
            organization_id=current_user.organization_id,
            month=month,
            class_id=class_id,
            session_id=session_id,
            user_id=user_id,
            status=status,
        )
        .order_by(
            models.Attendance.attendance_date.desc(),
            models.Attendance.check_in_time.desc(),
        )
        .all()
    )

    content = services.create_excel_report(records)

    return Response(
        content=content,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={
            "Content-Disposition": f'attachment; filename="attendance_{month}.xlsx"'
        },
    )


@app.get("/report/pdf/{month}")
def report_pdf(
    month: str,
    class_id: Optional[str] = None,
    session_id: Optional[str] = None,
    user_id: Optional[str] = None,
    status: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    class_id, session_id, user_id = normalize_report_scope_for_role(
        current_user,
        class_id=class_id,
        session_id=session_id,
        user_id=user_id,
    )

    records = (
        report_records_query(
            db,
            organization_id=current_user.organization_id,
            month=month,
            class_id=class_id,
            session_id=session_id,
            user_id=user_id,
            status=status,
        )
        .order_by(
            models.Attendance.attendance_date.desc(),
            models.Attendance.check_in_time.desc(),
        )
        .all()
    )

    content = services.create_pdf_report(f"Attendance report {month}", records)

    return Response(
        content=content,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="attendance_{month}.pdf"'
        },
    )
# ---------------------------------------------------------------------------
# Audit Logs
# ---------------------------------------------------------------------------

@app.get("/audit-logs", response_model=list[schemas.AuditLogOut])
def list_audit_logs(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_roles("admin")),
):
    return (
        db.query(models.AuditLog)
        .filter(models.AuditLog.organization_id == current_user.organization_id)
        .order_by(models.AuditLog.created_at.desc())
        .limit(500)
        .all()
    )


# ---------------------------------------------------------------------------
# WebSocket
# ---------------------------------------------------------------------------

@app.websocket("/ws/{organization_id}")
async def websocket_endpoint(
    websocket: WebSocket,
    organization_id: str,
    token: Optional[str] = None,
    db: Session = Depends(get_db),
):
    # Realtime socket-г заавал access token-той холбох.
    if not token:
        await websocket.close(code=4401)
        return

    payload = decode_token(token)
    if not payload or payload.get("type") != "access":
        await websocket.close(code=4401)
        return

    if payload.get("org") != organization_id:
        await websocket.close(code=4403)
        return

    # Token дээрх user одоо ч идэвхтэй, тухайн байгууллагад харьяалагдаж байгаа эсэх.
    user = (
        db.query(models.User)
        .filter(
            models.User.id == payload.get("sub"),
            models.User.organization_id == organization_id,
            models.User.is_active == True,
        )
        .first()
    )
    if not user:
        await websocket.close(code=4401)
        return

    await manager.connect(organization_id, websocket)
    try:
        while True:
            data = await websocket.receive_json()
            await manager.broadcast(organization_id, data)
    except WebSocketDisconnect:
        manager.disconnect(organization_id, websocket)


# ---------------------------------------------------------------------------
# Push tokens
# ---------------------------------------------------------------------------

@app.post("/push-tokens", response_model=schemas.PushTokenOut)
def register_push_token(
    body: schemas.PushTokenRegisterRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    device = (
        db.query(models.Device)
        .filter(
            models.Device.uuid == body.device_uuid,
            models.Device.user_id == current_user.id,
            models.Device.is_registered == True,
            models.Device.is_active == True,
        )
        .first()
    )

    existing = (
        db.query(models.PushToken)
        .filter(models.PushToken.token == body.token)
        .first()
    )
    if existing:
        return existing

    push_token = models.PushToken(
        user_id=current_user.id,
        device_id=device.id if device else None,
        platform=body.platform,
        token=body.token,
    )
    db.add(push_token)
    db.commit()
    db.refresh(push_token)
    return push_token


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

@app.get("/health")
def health():
    return {"status": "ok", "timestamp": services.app_now_naive().isoformat()}
