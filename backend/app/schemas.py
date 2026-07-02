from datetime import date, datetime, time
from typing import Any, Optional

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator


class MessageResponse(BaseModel):
    message: str


class LoginRequest(BaseModel):
    username: str
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class LogoutRequest(BaseModel):
    refresh_token: str


class LoginResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user_id: str
    role: str
    organization_id: str


class UserBase(BaseModel):
    id: str
    organization_id: str
    department_id: Optional[str] = None
    username: str
    full_name: str
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    role: str = "student"
    is_active: bool = True


class UserCreate(UserBase):
    password: str = Field(min_length=6)


class UserUpdate(BaseModel):
    department_id: Optional[str] = None
    full_name: Optional[str] = None
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    role: Optional[str] = None
    is_active: Optional[bool] = None


class UserOut(UserBase):
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class DeviceBase(BaseModel):
    uuid: str
    name: Optional[str] = None
    platform: Optional[str] = None
    device_type: Optional[str] = None
    is_registered: bool = True
    is_active: bool = True


class DeviceCreate(DeviceBase):
    user_id: str


class DeviceUpdate(BaseModel):
    name: Optional[str] = None
    platform: Optional[str] = None
    device_type: Optional[str] = None
    is_registered: Optional[bool] = None
    is_active: Optional[bool] = None


class DeviceOut(DeviceBase):
    id: int
    user_id: str
    verified_at: Optional[datetime] = None
    revoked_at: Optional[datetime] = None
    last_seen_at: Optional[datetime] = None
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class RoomBase(BaseModel):
    id: str
    organization_id: str
    name: str
    building: Optional[str] = None
    floor: Optional[str] = None
    capacity: Optional[int] = None
    description: Optional[str] = None


class RoomCreate(RoomBase):
    pass


class RoomUpdate(BaseModel):
    name: Optional[str] = None
    building: Optional[str] = None
    floor: Optional[str] = None
    capacity: Optional[int] = None
    description: Optional[str] = None


class RoomOut(RoomBase):
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class BeaconBase(BaseModel):
    id: str
    organization_id: str
    room_id: Optional[str] = None
    uuid: str
    major: Optional[str] = None
    minor: Optional[str] = None
    name: str
    advertiser_type: Optional[str] = None
    tx_power: Optional[int] = None
    threshold_distance: float = 2.0
    is_active: bool = True


class BeaconCreate(BeaconBase):
    pass


class BeaconUpdate(BaseModel):
    room_id: Optional[str] = None
    uuid: Optional[str] = None
    major: Optional[str] = None
    minor: Optional[str] = None
    name: Optional[str] = None
    advertiser_type: Optional[str] = None
    tx_power: Optional[int] = None
    threshold_distance: Optional[float] = None
    is_active: Optional[bool] = None


class BeaconOut(BeaconBase):
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class ClassOrShiftBase(BaseModel):
    id: str
    organization_id: str
    department_id: str
    teacher_id: Optional[str] = None
    room_id: Optional[str] = None
    beacon_id: Optional[str] = None
    name: str
    code: Optional[str] = None
    type: str = "class"
    day_of_week: Optional[str] = None
    start_time: Optional[time] = None
    end_time: Optional[time] = None
    semester_start_date: Optional[date] = None
    semester_end_date: Optional[date] = None
    late_after_minutes: int = 10
    is_active: bool = True


class ClassOrShiftCreate(ClassOrShiftBase):
    @field_validator("end_time")
    @classmethod
    def validate_end_time(cls, value: Optional[time], info):
        start_time = info.data.get("start_time")
        if start_time and value and value <= start_time:
            raise ValueError("end_time must be greater than start_time")
        return value


class ClassOrShiftUpdate(BaseModel):
    teacher_id: Optional[str] = None
    room_id: Optional[str] = None
    beacon_id: Optional[str] = None
    name: Optional[str] = None
    code: Optional[str] = None
    type: Optional[str] = None
    day_of_week: Optional[str] = None
    start_time: Optional[time] = None
    end_time: Optional[time] = None
    semester_start_date: Optional[date] = None
    semester_end_date: Optional[date] = None
    late_after_minutes: Optional[int] = None
    is_active: Optional[bool] = None


class ClassOrShiftOut(ClassOrShiftBase):
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)

class ClassStudentCreate(BaseModel):
    user_id: str


class ClassStudentOut(BaseModel):
    id: int
    organization_id: str
    class_or_shift_id: str
    user_id: str
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)



class SessionBase(BaseModel):
    id: str
    organization_id: str
    class_or_shift_id: str
    beacon_id: Optional[str] = None
    session_date: date
    start_time: Optional[time] = None
    end_time: Optional[time] = None
    is_open: bool = True


class SessionCreate(SessionBase):
    @field_validator("end_time")
    @classmethod
    def validate_end_time(cls, value: Optional[time], info):
        start_time = info.data.get("start_time")
        if start_time and value and value <= start_time:
            raise ValueError("end_time must be greater than start_time")
        return value


class SessionUpdate(BaseModel):
    beacon_id: Optional[str] = None
    session_date: Optional[date] = None
    start_time: Optional[time] = None
    end_time: Optional[time] = None
    is_open: Optional[bool] = None


class SessionOut(SessionBase):
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class AttendanceRequest(BaseModel):
    user_id: str
    session_id: str
    device_uuid: str
    beacon_uuid: str
    major: Optional[str] = None
    minor: Optional[str] = None
    rssi: Optional[int] = Field(default=None, ge=-110, le=-20)
    rssi_samples: list[int] = Field(default_factory=list)
    distance: Optional[float] = Field(default=None, ge=0, le=50)
    note: Optional[str] = None
    client_timestamp: datetime
    nonce: str = Field(min_length=8, max_length=128)

    @field_validator("rssi_samples")
    @classmethod
    def validate_rssi_samples(cls, value: list[int]):
        if len(value) > 20:
            raise ValueError("rssi_samples must contain 20 or fewer readings")
        if any(sample < -110 or sample > -20 for sample in value):
            raise ValueError("rssi_samples values must be between -110 and -20")
        return value


class AttendanceCheckoutRequest(BaseModel):
    session_id: str
    device_uuid: str
    client_timestamp: datetime
    nonce: str = Field(min_length=8, max_length=128)
    note: Optional[str] = None


class AttendanceSyncRequest(BaseModel):
    # 'check_in' эсвэл 'check_out'
    type: str
    # Offline үед хадгалсан original check_in/check_out payload
    payload: dict[str, Any]
    # BLE илэрсэн бодит цаг. Report/history-д энэ цаг ашиглагдана.
    detected_at: datetime
    # Sync хийх мөчийн цаг. Nonce freshness шалгалтад ашиглана.
    sync_timestamp: datetime
    nonce: str = Field(min_length=8, max_length=128)


class ManualAttendanceUpdateRequest(BaseModel):
    status: Optional[str] = None
    note: Optional[str] = None
    check_in_time: Optional[datetime] = None
    check_out_time: Optional[datetime] = None
    reason: str = Field(min_length=3)


class AttendanceOut(BaseModel):
    id: int
    organization_id: str
    session_id: str
    user_id: str
    device_id: Optional[int] = None
    beacon_id: Optional[str] = None
    attendance_date: date
    check_in_time: datetime
    check_out_time: Optional[datetime] = None
    distance_m: Optional[float] = None
    rssi: Optional[int] = None
    rssi_variance: Optional[float] = None
    status: str
    detection_method: str
    late_minutes: int
    note: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)


class AttendanceFilter(BaseModel):
    from_date: Optional[date] = None
    to_date: Optional[date] = None
    status: Optional[str] = None


class PushTokenRegisterRequest(BaseModel):
    device_uuid: str
    platform: str
    token: str


class PushTokenOut(BaseModel):
    id: int
    user_id: str
    device_id: Optional[int] = None
    platform: str
    token: str
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class AuditLogOut(BaseModel):
    id: int
    organization_id: str
    actor_user_id: Optional[str] = None
    action: str
    entity_type: str
    entity_id: str
    old_value: Optional[str] = None
    new_value: Optional[str] = None
    reason: Optional[str] = None
    ip_address: Optional[str] = None
    created_at: datetime
    model_config = ConfigDict(from_attributes=True)


class DashboardEvent(BaseModel):
    type: str
    payload: dict[str, Any]
class AttendanceAppealCreate(BaseModel):
    attendance_id: Optional[int] = None
    session_id: str
    reason_type: str
    message: str


class AttendanceAppealReview(BaseModel):
    status: str
    review_note: Optional[str] = None

    # Approve хийх үед attendance засах бол эдгээрийг дамжуулж болно
    correction_status: Optional[str] = None
    correction_note: Optional[str] = None
    correction_check_in_time: Optional[datetime] = None
    correction_check_out_time: Optional[datetime] = None
    correction_late_minutes: Optional[int] = None


class AttendanceAppealOut(BaseModel):
    id: int
    organization_id: str
    attendance_id: Optional[int] = None
    user_id: str
    session_id: str
    reason_type: str
    message: str
    status: str
    reviewed_by: Optional[str] = None
    review_note: Optional[str] = None
    created_at: datetime
    reviewed_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class TeacherSessionSummaryItem(BaseModel):
    session_id: str
    class_or_shift_id: str
    class_name: str
    room_name: str
    session_date: str
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    is_open: bool
    total_students: int
    present: int
    late: int
    checked_out: int
    absent: int
    attendance_rate: float


class TeacherSessionSummaryResponse(BaseModel):
    teacher_id: str
    today: str
    sessions: list[TeacherSessionSummaryItem]


class ActiveSessionOut(BaseModel):
    session_id: str
    class_or_shift_id: str
    class_name: str
    room_name: str = "-"
    beacon_id: Optional[str] = None
    beacon_uuid: str
    major: Optional[str] = None
    minor: Optional[str] = None
    tx_power: Optional[int] = None
    threshold_distance: float = 3.0
    session_date: date
    start_time: Optional[time] = None
    end_time: Optional[time] = None
    is_open: bool = True
