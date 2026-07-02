from datetime import datetime, date, time

from sqlalchemy import (
    Boolean,
    Column,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    Time,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from database import Base


class Organization(Base):
    __tablename__ = "organizations"

    id = Column(String, primary_key=True, index=True)
    name = Column(String, nullable=False, unique=True)
    description = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    departments = relationship("Department", back_populates="organization", cascade="all, delete-orphan")
    users = relationship("User", back_populates="organization", cascade="all, delete-orphan")
    rooms = relationship("Room", back_populates="organization", cascade="all, delete-orphan")
    beacons = relationship("Beacon", back_populates="organization", cascade="all, delete-orphan")


class Department(Base):
    __tablename__ = "departments"

    id = Column(String, primary_key=True, index=True)
    organization_id = Column(String, ForeignKey("organizations.id"), nullable=False, index=True)
    name = Column(String, nullable=False)
    description = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    organization = relationship("Organization", back_populates="departments")
    users = relationship("User", back_populates="department")
    classes_or_shifts = relationship("ClassOrShift", back_populates="department")

    __table_args__ = (
        UniqueConstraint("organization_id", "name", name="uq_department_org_name"),
    )


class User(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True, index=True)
    organization_id = Column(String, ForeignKey("organizations.id"), nullable=False, index=True)
    department_id = Column(String, ForeignKey("departments.id"), nullable=True, index=True)

    username = Column(String, nullable=False, unique=True, index=True)
    full_name = Column(String, nullable=False)
    email = Column(String, nullable=True, unique=True, index=True)
    phone = Column(String, nullable=True)

    hashed_password = Column(String, nullable=False)
    role = Column(String, nullable=False, default="student")

    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    organization = relationship("Organization", back_populates="users")
    department = relationship("Department", back_populates="users")

    devices = relationship("Device", back_populates="user", cascade="all, delete-orphan")
    attendances = relationship("Attendance", back_populates="user")
    teaching_classes = relationship("ClassOrShift", back_populates="teacher")
    class_enrollments = relationship("ClassStudent", back_populates="student", cascade="all, delete-orphan")
    refresh_tokens = relationship("RefreshToken", back_populates="user", cascade="all, delete-orphan")
    push_tokens = relationship("PushToken", back_populates="user", cascade="all, delete-orphan")
    audit_logs = relationship("AuditLog", back_populates="actor")


class Device(Base):
    __tablename__ = "devices"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)

    uuid = Column(String, nullable=False, unique=True, index=True)
    name = Column(String, nullable=True)
    platform = Column(String, nullable=True)
    device_type = Column(String, nullable=True)

    is_registered = Column(Boolean, default=True, nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    verified_at = Column(DateTime, nullable=True)
    revoked_at = Column(DateTime, nullable=True)
    last_seen_at = Column(DateTime, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    user = relationship("User", back_populates="devices")
    attendances = relationship("Attendance", back_populates="device")
    push_tokens = relationship("PushToken", back_populates="device", cascade="all, delete-orphan")


class Room(Base):
    __tablename__ = "rooms"

    id = Column(String, primary_key=True, index=True)
    organization_id = Column(String, ForeignKey("organizations.id"), nullable=False, index=True)

    name = Column(String, nullable=False)
    building = Column(String, nullable=True)
    floor = Column(String, nullable=True)
    capacity = Column(Integer, nullable=True)
    description = Column(Text, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    organization = relationship("Organization", back_populates="rooms")
    beacons = relationship("Beacon", back_populates="room")
    classes_or_shifts = relationship("ClassOrShift", back_populates="room")

    __table_args__ = (
        UniqueConstraint("organization_id", "name", name="uq_room_org_name"),
    )


class Beacon(Base):
    __tablename__ = "beacons"

    id = Column(String, primary_key=True, index=True)
    organization_id = Column(String, ForeignKey("organizations.id"), nullable=False, index=True)
    room_id = Column(String, ForeignKey("rooms.id"), nullable=True, index=True)

    uuid = Column(String, nullable=False, index=True)
    major = Column(String, nullable=True)
    minor = Column(String, nullable=True)

    name = Column(String, nullable=False)
    advertiser_type = Column(String, nullable=True)
    tx_power = Column(Integer, nullable=True)
    threshold_distance = Column(Float, default=2.0, nullable=False)

    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    organization = relationship("Organization", back_populates="beacons")
    room = relationship("Room", back_populates="beacons")
    classes_or_shifts = relationship("ClassOrShift", back_populates="beacon")
    attendance_sessions = relationship("AttendanceSession", back_populates="beacon")

    __table_args__ = (
        UniqueConstraint("organization_id", "uuid", "major", "minor", name="uq_beacon_org_identity"),
        Index("ix_beacon_identity_lookup", "uuid", "major", "minor"),
    )


class ClassOrShift(Base):
    __tablename__ = "classes_or_shifts"

    id = Column(String, primary_key=True, index=True)
    organization_id = Column(String, ForeignKey("organizations.id"), nullable=False, index=True)
    department_id = Column(String, ForeignKey("departments.id"), nullable=False, index=True)
    teacher_id = Column(String, ForeignKey("users.id"), nullable=True, index=True)
    room_id = Column(String, ForeignKey("rooms.id"), nullable=True, index=True)
    beacon_id = Column(String, ForeignKey("beacons.id"), nullable=True, index=True)

    name = Column(String, nullable=False)
    code = Column(String, nullable=True)
    type = Column(String, nullable=False, default="class")
    day_of_week = Column(String, nullable=True)
    start_time = Column(Time, nullable=True)
    end_time = Column(Time, nullable=True)

    semester_start_date = Column(Date, nullable=True)
    semester_end_date = Column(Date, nullable=True)

    late_after_minutes = Column(Integer, default=10, nullable=False)

    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    department = relationship("Department", back_populates="classes_or_shifts")
    teacher = relationship("User", back_populates="teaching_classes")
    room = relationship("Room", back_populates="classes_or_shifts")
    beacon = relationship("Beacon", back_populates="classes_or_shifts")
    sessions = relationship("AttendanceSession", back_populates="class_or_shift", cascade="all, delete-orphan")
    students = relationship("ClassStudent", back_populates="class_or_shift", cascade="all, delete-orphan")


class ClassStudent(Base):
    __tablename__ = "class_students"

    id = Column(Integer, primary_key=True, autoincrement=True)
    organization_id = Column(String, ForeignKey("organizations.id"), nullable=False, index=True)
    class_or_shift_id = Column(String, ForeignKey("classes_or_shifts.id"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    class_or_shift = relationship("ClassOrShift", back_populates="students")
    student = relationship("User", back_populates="class_enrollments")

    __table_args__ = (
        UniqueConstraint("class_or_shift_id", "user_id", name="uq_class_student"),
        Index("ix_class_students_org_class", "organization_id", "class_or_shift_id"),
        Index("ix_class_students_user", "user_id"),
    )


class AttendanceSession(Base):
    __tablename__ = "attendance_sessions"

    id = Column(String, primary_key=True, index=True)
    organization_id = Column(String, ForeignKey("organizations.id"), nullable=False, index=True)
    class_or_shift_id = Column(String, ForeignKey("classes_or_shifts.id"), nullable=False, index=True)
    beacon_id = Column(String, ForeignKey("beacons.id"), nullable=True, index=True)

    session_date = Column(Date, nullable=False, index=True)
    start_time = Column(Time, nullable=True)
    end_time = Column(Time, nullable=True)

    is_open = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    class_or_shift = relationship("ClassOrShift", back_populates="sessions")
    beacon = relationship("Beacon", back_populates="attendance_sessions")
    attendances = relationship("Attendance", back_populates="session", cascade="all, delete-orphan")


class Attendance(Base):
    __tablename__ = "attendances"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    organization_id = Column(String, ForeignKey("organizations.id"), nullable=False, index=True)
    session_id = Column(String, ForeignKey("attendance_sessions.id"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    device_id = Column(Integer, ForeignKey("devices.id"), nullable=True, index=True)
    beacon_id = Column(String, ForeignKey("beacons.id"), nullable=True, index=True)

    attendance_date = Column(Date, default=date.today, nullable=False, index=True)
    check_in_time = Column(DateTime, default=datetime.utcnow, nullable=False)
    check_out_time = Column(DateTime, nullable=True)

    distance_m = Column(Float, nullable=True)
    rssi = Column(Integer, nullable=True)
    rssi_variance = Column(Float, nullable=True)

    status = Column(String, default="present", nullable=False)
    detection_method = Column(String, default="ble", nullable=False)
    late_minutes = Column(Integer, default=0, nullable=False)
    note = Column(Text, nullable=True)

    session = relationship("AttendanceSession", back_populates="attendances")
    user = relationship("User", back_populates="attendances")
    device = relationship("Device", back_populates="attendances")

    __table_args__ = (
        UniqueConstraint("session_id", "user_id", name="uq_attendance_session_user"),
        Index("ix_attendance_user_date", "user_id", "attendance_date"),
        Index("ix_attendance_session_status", "session_id", "status"),
        Index("ix_attendance_beacon_time", "beacon_id", "check_in_time"),
    )


class AttendanceNonce(Base):
    __tablename__ = "attendance_nonces"

    id = Column(Integer, primary_key=True, autoincrement=True)
    organization_id = Column(String, ForeignKey("organizations.id"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    nonce = Column(String, nullable=False, unique=True, index=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    token = Column(String, nullable=False, unique=True, index=True)
    expires_at = Column(DateTime, nullable=False)
    revoked_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    user = relationship("User", back_populates="refresh_tokens")


class PushToken(Base):
    __tablename__ = "push_tokens"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    device_id = Column(Integer, ForeignKey("devices.id"), nullable=True, index=True)
    platform = Column(String, nullable=False)
    token = Column(String, nullable=False, unique=True, index=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    user = relationship("User", back_populates="push_tokens")
    device = relationship("Device", back_populates="push_tokens")


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    organization_id = Column(String, ForeignKey("organizations.id"), nullable=False, index=True)
    actor_user_id = Column(String, ForeignKey("users.id"), nullable=True, index=True)
    action = Column(String, nullable=False)
    entity_type = Column(String, nullable=False)
    entity_id = Column(String, nullable=False)
    old_value = Column(Text, nullable=True)
    new_value = Column(Text, nullable=True)
    reason = Column(Text, nullable=True)
    ip_address = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    actor = relationship("User", back_populates="audit_logs")
class AttendanceAppeal(Base):
    __tablename__ = "attendance_appeals"

    id = Column(Integer, primary_key=True, autoincrement=True)
    organization_id = Column(String, ForeignKey("organizations.id"), nullable=False, index=True)

    attendance_id = Column(Integer, ForeignKey("attendances.id"), nullable=True, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    session_id = Column(String, ForeignKey("attendance_sessions.id"), nullable=False, index=True)

    reason_type = Column(String, nullable=False)
    message = Column(Text, nullable=False)

    status = Column(String, default="pending", nullable=False, index=True)
    reviewed_by = Column(String, ForeignKey("users.id"), nullable=True, index=True)
    review_note = Column(Text, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    reviewed_at = Column(DateTime, nullable=True)