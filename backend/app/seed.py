import os
from datetime import date, time

import models
from auth import hash_password
from database import Base, SessionLocal, engine

Base.metadata.create_all(bind=engine)


ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD")
TEACHER_PASSWORD = os.getenv("TEACHER_PASSWORD")
STUDENT_PASSWORD = os.getenv("STUDENT_PASSWORD")

# iPad / BLE advertiser дээр харагдаж байгаа яг нэр эсвэл service UUID-г эндээс тохируулж болно.
# Жишээ: BEA003_UUID=ipad эсвэл BEA003_UUID=BEA003
BEA003_UUID = os.getenv("BEA003_UUID", "ipad")


def require_seed_password(value: str | None, name: str) -> str:
    if not value or len(value) < 6:
        raise RuntimeError(f"{name} must be set and at least 6 characters long before seeding")
    return value


def seed() -> None:
    db = SessionLocal()

    try:
        admin_password = require_seed_password(ADMIN_PASSWORD, "ADMIN_PASSWORD")
        teacher_password = require_seed_password(TEACHER_PASSWORD, "TEACHER_PASSWORD")
        student_password = require_seed_password(STUDENT_PASSWORD, "STUDENT_PASSWORD")

        # ---------------------------
        # ORGANIZATION
        # ---------------------------
        org = db.get(models.Organization, "ORG001")
        if not org:
            org = models.Organization(
                id="ORG001",
                name="Demo University",
                description="Demo organization for BLE attendance system",
            )
            db.add(org)
            db.commit()
            db.refresh(org)
        else:
            org.name = "Demo University"
            org.description = "Demo organization for BLE attendance system"
            db.commit()

        # ---------------------------
        # DEPARTMENT
        # ---------------------------
        dept = db.get(models.Department, "DEP001")
        if not dept:
            dept = models.Department(
                id="DEP001",
                organization_id="ORG001",
                name="Information Technology Department",
                description="Demo department for IT projects",
            )
            db.add(dept)
            db.commit()
            db.refresh(dept)
        else:
            dept.organization_id = "ORG001"
            dept.name = "Information Technology Department"
            dept.description = "Demo department for IT projects"
            db.commit()

        # ---------------------------
        # USERS
        # ---------------------------
        admin = db.get(models.User, "ADMIN001")
        if not admin:
            admin = models.User(
                id="ADMIN001",
                organization_id="ORG001",
                department_id="DEP001",
                username="admin",
                full_name="Demo Admin",
                email="admin@example.com",
                phone="99000001",
                hashed_password=hash_password(admin_password),
                role="admin",
                is_active=True,
            )
            db.add(admin)
            db.commit()
            db.refresh(admin)
        else:
            admin.organization_id = "ORG001"
            admin.department_id = "DEP001"
            admin.username = "admin"
            admin.full_name = "Demo Admin"
            admin.email = "admin@example.com"
            admin.phone = "99000001"
            admin.hashed_password = hash_password(admin_password)
            admin.role = "admin"
            admin.is_active = True
            db.commit()

        teacher = db.get(models.User, "TEACH001")
        if not teacher:
            teacher = models.User(
                id="TEACH001",
                organization_id="ORG001",
                department_id="DEP001",
                username="teacher1",
                full_name="Demo Teacher",
                email="teacher@example.com",
                phone="99000002",
                hashed_password=hash_password(teacher_password),
                role="teacher",
                is_active=True,
            )
            db.add(teacher)
            db.commit()
            db.refresh(teacher)
        else:
            teacher.organization_id = "ORG001"
            teacher.department_id = "DEP001"
            teacher.username = "teacher1"
            teacher.full_name = "Demo Teacher"
            teacher.email = "teacher@example.com"
            teacher.phone = "99000002"
            teacher.hashed_password = hash_password(teacher_password)
            teacher.role = "teacher"
            teacher.is_active = True
            db.commit()

        student = db.get(models.User, "STUDENT001")
        if not student:
            student = models.User(
                id="STUDENT001",
                organization_id="ORG001",
                department_id="DEP001",
                username="student001",
                full_name="Demo Student",
                email="student@example.com",
                phone="99000003",
                hashed_password=hash_password(student_password),
                role="student",
                is_active=True,
            )
            db.add(student)
            db.commit()
            db.refresh(student)
        else:
            student.organization_id = "ORG001"
            student.department_id = "DEP001"
            student.username = "student001"
            student.full_name = "Demo Student"
            student.email = "student@example.com"
            student.phone = "99000003"
            student.hashed_password = hash_password(student_password)
            student.role = "student"
            student.is_active = True
            db.commit()

        # ---------------------------
        # ROOMS
        # ---------------------------
        room401 = db.get(models.Room, "ROOM401")
        if not room401:
            room401 = models.Room(
                id="ROOM401",
                organization_id="ORG001",
                name="Lab 401",
                building="ICT Building",
                floor="4",
                capacity=40,
                description="BLE attendance laboratory room",
            )
            db.add(room401)
            db.commit()
        else:
            room401.organization_id = "ORG001"
            room401.name = "Lab 401"
            room401.building = "ICT Building"
            room401.floor = "4"
            room401.capacity = 40
            room401.description = "BLE attendance laboratory room"
            db.commit()

        room402 = db.get(models.Room, "ROOM402")
        if not room402:
            room402 = models.Room(
                id="ROOM402",
                organization_id="ORG001",
                name="Room 402",
                building="ICT Building",
                floor="4",
                capacity=35,
                description="Mobile demo room",
            )
            db.add(room402)
            db.commit()
        else:
            room402.organization_id = "ORG001"
            room402.name = "Room 402"
            room402.building = "ICT Building"
            room402.floor = "4"
            room402.capacity = 35
            room402.description = "Mobile demo room"
            db.commit()

        room403 = db.get(models.Room, "ROOM403")
        if not room403:
            room403 = models.Room(
                id="ROOM403",
                organization_id="ORG001",
                name="Smart Classroom",
                building="ICT Building",
                floor="4",
                capacity=30,
                description="iPad beacon demo room",
            )
            db.add(room403)
            db.commit()
        else:
            room403.organization_id = "ORG001"
            room403.name = "Smart Classroom"
            room403.building = "ICT Building"
            room403.floor = "4"
            room403.capacity = 30
            room403.description = "iPad beacon demo room"
            db.commit()

        # ---------------------------
        # BEACONS
        # ---------------------------
        beacon1 = db.get(models.Beacon, "BEA001")
        if not beacon1:
            beacon1 = models.Beacon(
                id="BEA001",
                organization_id="ORG001",
                room_id="ROOM401",
                uuid="MAC-ADVERTISER-UUID",
                major="1",
                minor="1",
                name="Mac Advertiser",
                advertiser_type="mac",
                tx_power=-59,
                threshold_distance=2.0,
                is_active=True,
            )
            db.add(beacon1)
            db.commit()
        else:
            beacon1.organization_id = "ORG001"
            beacon1.room_id = "ROOM401"
            beacon1.uuid = "MAC-ADVERTISER-UUID"
            beacon1.major = "1"
            beacon1.minor = "1"
            beacon1.name = "Mac Advertiser"
            beacon1.advertiser_type = "mac"
            beacon1.tx_power = -59
            beacon1.threshold_distance = 2.0
            beacon1.is_active = True
            db.commit()

        beacon2 = db.get(models.Beacon, "BEA002")
        if not beacon2:
            beacon2 = models.Beacon(
                id="BEA002",
                organization_id="ORG001",
                room_id="ROOM402",
                uuid="BLE Advertiser",
                major="1",
                minor="1",
                name="iPad BLE Advertiser",
                advertiser_type="ipad",
                tx_power=-59,
                threshold_distance=3.0,
                is_active=True,
            )
            db.add(beacon2)
            db.commit()
        else:
            beacon2.organization_id = "ORG001"
            beacon2.room_id = "ROOM402"
            beacon2.uuid = "BLE Advertiser"
            beacon2.major = "1"
            beacon2.minor = "1"
            beacon2.name = "iPad BLE Advertiser"
            beacon2.advertiser_type = "ipad"
            beacon2.tx_power = -59
            beacon2.threshold_distance = 3.0
            beacon2.is_active = True
            db.commit()

        beacon3 = db.get(models.Beacon, "BEA003")
        if not beacon3:
            beacon3 = models.Beacon(
                id="BEA003",
                organization_id="ORG001",
                room_id="ROOM403",
                uuid=BEA003_UUID,
                major="1",
                minor="1",
                name="iPad Beacon",
                advertiser_type="ipad",
                tx_power=-59,
                threshold_distance=3.0,
                is_active=True,
            )
            db.add(beacon3)
            db.commit()
        else:
            beacon3.organization_id = "ORG001"
            beacon3.room_id = "ROOM403"
            beacon3.uuid = BEA003_UUID
            beacon3.major = "1"
            beacon3.minor = "1"
            beacon3.name = "iPad Beacon"
            beacon3.advertiser_type = "ipad"
            beacon3.tx_power = -59
            beacon3.threshold_distance = 3.0
            beacon3.is_active = True
            db.commit()

        # ---------------------------
        # DEVICES
        # ---------------------------
        student_device = db.query(models.Device).filter_by(uuid="DEVICE_STUDENT001").first()
        if not student_device:
            student_device = models.Device(
                user_id="STUDENT001",
                uuid="DEVICE_STUDENT001",
                name="Student Demo Phone",
                platform="iOS",
                device_type="phone",
                is_registered=True,
                is_active=True,
            )
            db.add(student_device)
            db.commit()
        else:
            student_device.user_id = "STUDENT001"
            student_device.name = "Student Demo Phone"
            student_device.platform = "iOS"
            student_device.device_type = "phone"
            student_device.is_registered = True
            student_device.is_active = True
            db.commit()

        teacher_device = db.query(models.Device).filter_by(uuid="DEVICE_TEACH001").first()
        if not teacher_device:
            teacher_device = models.Device(
                user_id="TEACH001",
                uuid="DEVICE_TEACH001",
                name="Teacher iPhone",
                platform="iOS",
                device_type="phone",
                is_registered=True,
                is_active=True,
            )
            db.add(teacher_device)
            db.commit()
        else:
            teacher_device.user_id = "TEACH001"
            teacher_device.name = "Teacher iPhone"
            teacher_device.platform = "iOS"
            teacher_device.device_type = "phone"
            teacher_device.is_registered = True
            teacher_device.is_active = True
            db.commit()

        admin_device = db.query(models.Device).filter_by(uuid="DEVICE_ADMIN001").first()
        if not admin_device:
            admin_device = models.Device(
                user_id="ADMIN001",
                uuid="DEVICE_ADMIN001",
                name="Admin MacBook",
                platform="macOS",
                device_type="laptop",
                is_registered=True,
                is_active=True,
            )
            db.add(admin_device)
            db.commit()
        else:
            admin_device.user_id = "ADMIN001"
            admin_device.name = "Admin MacBook"
            admin_device.platform = "macOS"
            admin_device.device_type = "laptop"
            admin_device.is_registered = True
            admin_device.is_active = True
            db.commit()

        # ---------------------------
        # CLASSES / SHIFTS
        # ---------------------------
        class1 = db.get(models.ClassOrShift, "CLASS001")
        if not class1:
            class1 = models.ClassOrShift(
                id="CLASS001",
                organization_id="ORG001",
                department_id="DEP001",
                teacher_id="TEACH001",
                room_id="ROOM401",
                beacon_id="BEA001",
                name="BLE Attendance Class",
                code="ICT401",
                type="class",
                day_of_week="Monday",
                start_time=time(8, 30),
                end_time=time(10, 0),
                late_after_minutes=10,
                is_active=True,
            )
            db.add(class1)
            db.commit()
        else:
            class1.organization_id = "ORG001"
            class1.department_id = "DEP001"
            class1.teacher_id = "TEACH001"
            class1.room_id = "ROOM401"
            class1.beacon_id = "BEA001"
            class1.name = "BLE Attendance Class"
            class1.code = "ICT401"
            class1.type = "class"
            class1.day_of_week = "Monday"
            class1.start_time = time(8, 30)
            class1.end_time = time(10, 0)
            class1.late_after_minutes = 10
            class1.is_active = True
            db.commit()

        class2 = db.get(models.ClassOrShift, "CLASS002")
        if not class2:
            class2 = models.ClassOrShift(
                id="CLASS002",
                organization_id="ORG001",
                department_id="DEP001",
                teacher_id="TEACH001",
                room_id="ROOM402",
                beacon_id="BEA002",
                name="Mobile BLE Demo Class",
                code="BLE402",
                type="class",
                day_of_week="Tuesday",
                start_time=time(8, 0),
                end_time=time(18, 0),
                late_after_minutes=10,
                is_active=True,
            )
            db.add(class2)
            db.commit()
        else:
            class2.organization_id = "ORG001"
            class2.department_id = "DEP001"
            class2.teacher_id = "TEACH001"
            class2.room_id = "ROOM402"
            class2.beacon_id = "BEA002"
            class2.name = "Mobile BLE Demo Class"
            class2.code = "BLE402"
            class2.type = "class"
            class2.day_of_week = "Tuesday"
            class2.start_time = time(8, 0)
            class2.end_time = time(18, 0)
            class2.late_after_minutes = 10
            class2.is_active = True
            db.commit()

        class3 = db.get(models.ClassOrShift, "CLASS003")
        if not class3:
            class3 = models.ClassOrShift(
                id="CLASS003",
                organization_id="ORG001",
                department_id="DEP001",
                teacher_id="TEACH001",
                room_id="ROOM403",
                beacon_id="BEA003",
                name="iPad Beacon Class",
                code="BLE403",
                type="class",
                day_of_week="Wednesday",
                start_time=time(9, 0),
                end_time=time(11, 0),
                late_after_minutes=10,
                is_active=True,
            )
            db.add(class3)
            db.commit()
        else:
            class3.organization_id = "ORG001"
            class3.department_id = "DEP001"
            class3.teacher_id = "TEACH001"
            class3.room_id = "ROOM403"
            class3.beacon_id = "BEA003"
            class3.name = "iPad Beacon Class"
            class3.code = "BLE403"
            class3.type = "class"
            class3.day_of_week = "Wednesday"
            class3.start_time = time(9, 0)
            class3.end_time = time(11, 0)
            class3.late_after_minutes = 10
            class3.is_active = True
            db.commit()

        # ---------------------------
        # ATTENDANCE SESSIONS
        # ---------------------------
        session1 = db.get(models.AttendanceSession, "SESSION001")
        if not session1:
            session1 = models.AttendanceSession(
                id="SESSION001",
                organization_id="ORG001",
                class_or_shift_id="CLASS001",
                beacon_id="BEA001",
                session_date=date.today(),
                start_time=time(8, 30),
                end_time=time(10, 0),
                is_open=True,
            )
            db.add(session1)
            db.commit()
        else:
            session1.organization_id = "ORG001"
            session1.class_or_shift_id = "CLASS001"
            session1.beacon_id = "BEA001"
            session1.session_date = date.today()
            session1.start_time = time(8, 30)
            session1.end_time = time(10, 0)
            session1.is_open = True
            db.commit()

        session2 = db.get(models.AttendanceSession, "SESSION002")
        if not session2:
            session2 = models.AttendanceSession(
                id="SESSION002",
                organization_id="ORG001",
                class_or_shift_id="CLASS002",
                beacon_id="BEA002",
                session_date=date.today(),
                start_time=time(8, 0),
                end_time=time(18, 0),
                is_open=True,
            )
            db.add(session2)
            db.commit()
        else:
            session2.organization_id = "ORG001"
            session2.class_or_shift_id = "CLASS002"
            session2.beacon_id = "BEA002"
            session2.session_date = date.today()
            session2.start_time = time(8, 0)
            session2.end_time = time(18, 0)
            session2.is_open = True
            db.commit()

        session3 = db.get(models.AttendanceSession, "SESSION003")
        if not session3:
            session3 = models.AttendanceSession(
                id="SESSION003",
                organization_id="ORG001",
                class_or_shift_id="CLASS003",
                beacon_id="BEA003",
                session_date=date.today(),
                start_time=time(9, 0),
                end_time=time(11, 0),
                is_open=True,
            )
            db.add(session3)
            db.commit()
        else:
            session3.organization_id = "ORG001"
            session3.class_or_shift_id = "CLASS003"
            session3.beacon_id = "BEA003"
            session3.session_date = date.today()
            session3.start_time = time(9, 0)
            session3.end_time = time(11, 0)
            session3.is_open = True
            db.commit()

        # ---------------------------
        # CLASS ENROLLMENTS
        # ---------------------------
        for class_id in ["CLASS001", "CLASS002", "CLASS003"]:
            enrollment = (
                db.query(models.ClassStudent)
                .filter(
                    models.ClassStudent.class_or_shift_id == class_id,
                    models.ClassStudent.user_id == "STUDENT001",
                )
                .first()
            )
            if not enrollment:
                db.add(
                    models.ClassStudent(
                        organization_id="ORG001",
                        class_or_shift_id=class_id,
                        user_id="STUDENT001",
                    )
                )
                db.commit()

        print("✅ Seed completed successfully.")

    except Exception as exc:
        db.rollback()
        print("❌ Seed failed:", exc)
        raise
    finally:
        db.close()


if __name__ == "__main__":
    seed()
