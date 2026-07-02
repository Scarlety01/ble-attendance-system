import { useEffect, useMemo, useState } from "react";
import { api, getAttendance, login, logout } from "./api";

const tabs = [
  ["overview", "Overview"],
  ["attendance", "Attendance"],
  ["users", "Users"],
  ["classes", "Classes"],
  ["sessions", "Sessions"],
  ["reports", "Reports"],
  ["appeals", "Appeals"],
  ["audit", "Audit"]
];

const initialUser = {
  id: "",
  organization_id: "ORG001",
  department_id: "DEP001",
  username: "",
  full_name: "",
  email: "",
  phone: "",
  role: "student",
  is_active: true,
  password: ""
};

const initialClass = {
  id: "",
  organization_id: "ORG001",
  department_id: "DEP001",
  teacher_id: "",
  room_id: "",
  beacon_id: "",
  name: "",
  code: "",
  type: "class",
  day_of_week: "Monday",
  start_time: "",
  end_time: "",
  late_after_minutes: 10,
  is_active: true
};

const initialSession = {
  id: "",
  organization_id: "ORG001",
  class_or_shift_id: "",
  beacon_id: "",
  session_date: new Date().toISOString().slice(0, 10),
  start_time: "",
  end_time: "",
  is_open: true
};

const initialBeacon = {
  id: "",
  organization_id: "ORG001",
  room_id: "",
  uuid: "",
  major: "",
  minor: "",
  name: "",
  advertiser_type: "ipad",
  tx_power: -59,
  threshold_distance: 3,
  is_active: true
};

function cleanPayload(payload) {
  return Object.fromEntries(
    Object.entries(payload).filter(([, value]) => value !== "" && value !== undefined)
  );
}

function useMessage() {
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  const run = async (fn, success) => {
    setError("");
    setMessage("");
    try {
      const result = await fn();
      if (success) setMessage(success);
      return result;
    } catch (err) {
      setError(err.response?.data?.detail || err.message || "Request failed");
      throw err;
    }
  };

  return { message, error, setError, setMessage, run };
}

function Field({ label, children }) {
  return (
    <label className="field">
      <span>{label}</span>
      {children}
    </label>
  );
}

function TextInput({ value, onChange, placeholder, type = "text" }) {
  return (
    <input
      value={value ?? ""}
      onChange={(event) => onChange(event.target.value)}
      placeholder={placeholder}
      type={type}
    />
  );
}

function Status({ value }) {
  return <span className={`badge badge-${value || "default"}`}>{value || "-"}</span>;
}

function Table({ columns, rows, empty = "No records" }) {
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>{columns.map((col) => <th key={col.key}>{col.label}</th>)}</tr>
        </thead>
        <tbody>
          {rows.length === 0 ? (
            <tr>
              <td colSpan={columns.length} className="empty">{empty}</td>
            </tr>
          ) : rows.map((row, index) => (
            <tr key={row.id ?? `${row.user_id}-${row.session_id}-${index}`}>
              {columns.map((col) => (
                <td key={col.key}>{col.render ? col.render(row) : row[col.key]}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export default function App() {
  const [token, setToken] = useState(() => localStorage.getItem("access_token"));
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [activeTab, setActiveTab] = useState("overview");
  const [loading, setLoading] = useState(false);
  const [bootstrapped, setBootstrapped] = useState(false);
  const msg = useMessage();

  const [month, setMonth] = useState(() => new Date().toISOString().slice(0, 7));
  const [overview, setOverview] = useState(null);
  const [attendance, setAttendance] = useState([]);
  const [users, setUsers] = useState([]);
  const [devices, setDevices] = useState([]);
  const [classes, setClasses] = useState([]);
  const [sessions, setSessions] = useState([]);
  const [rooms, setRooms] = useState([]);
  const [beacons, setBeacons] = useState([]);
  const [appeals, setAppeals] = useState([]);
  const [auditLogs, setAuditLogs] = useState([]);
  const [report, setReport] = useState(null);

  const [userForm, setUserForm] = useState(initialUser);
  const [deviceForm, setDeviceForm] = useState({ user_id: "", uuid: "", name: "", platform: "iOS", device_type: "phone" });
  const [classForm, setClassForm] = useState(initialClass);
  const [sessionForm, setSessionForm] = useState(initialSession);
  const [beaconForm, setBeaconForm] = useState(initialBeacon);
  const [enrollForm, setEnrollForm] = useState({ class_id: "", user_id: "" });
  const [attendanceFilters, setAttendanceFilters] = useState({ user_id: "", session_id: "", class_id: "", status: "" });
  const [manualForm, setManualForm] = useState({ attendance_id: "", status: "present", note: "", reason: "" });
  const [appealReview, setAppealReview] = useState({ appeal_id: "", status: "approved", review_note: "" });

  const role = localStorage.getItem("role") || "";
  const studentUsers = useMemo(() => users.filter((user) => user.role === "student"), [users]);
  const teacherUsers = useMemo(() => users.filter((user) => user.role === "teacher"), [users]);

  const loadCore = async () => {
    const [
      overviewRes,
      attendanceRes,
      usersRes,
      devicesRes,
      roomsRes,
      beaconsRes,
      classesRes,
      sessionsRes,
      appealsRes,
      auditRes
    ] = await Promise.all([
      api.overview(month),
      api.attendance(attendanceFilters),
      api.users(),
      api.devices(),
      api.rooms(),
      api.beacons(),
      api.classes(),
      api.sessions(),
      api.appeals(),
      api.auditLogs()
    ]);

    setOverview(overviewRes.data);
    setAttendance(attendanceRes.data);
    setUsers(usersRes.data);
    setDevices(devicesRes.data);
    setRooms(roomsRes.data);
    setBeacons(beaconsRes.data);
    setClasses(classesRes.data);
    setSessions(sessionsRes.data);
    setAppeals(appealsRes.data);
    setAuditLogs(auditRes.data);
    setBootstrapped(true);
  };

  const refresh = async () => {
    setLoading(true);
    try {
      await msg.run(loadCore);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (token) refresh();
  }, [token, month]);

  const submitLogin = async (event) => {
    event.preventDefault();
    setLoading(true);
    try {
      const res = await msg.run(() => login({ username, password }), "Logged in");
      setToken(res.data.access_token);
      setPassword("");
    } finally {
      setLoading(false);
    }
  };

  const signOut = () => {
    logout();
    setToken(null);
    setBootstrapped(false);
  };

  const createUser = async (event) => {
    event.preventDefault();
    await msg.run(async () => {
      await api.createUser({ ...userForm, is_active: Boolean(userForm.is_active) });
      setUserForm(initialUser);
      await refresh();
    }, "User created");
  };

  const toggleUser = async (user) => {
    await msg.run(async () => {
      await api.updateUser(user.id, { is_active: !user.is_active });
      await refresh();
    }, "User updated");
  };

  const createDevice = async (event) => {
    event.preventDefault();
    await msg.run(async () => {
      await api.createDevice(cleanPayload(deviceForm));
      setDeviceForm({ user_id: "", uuid: "", name: "", platform: "iOS", device_type: "phone" });
      await refresh();
    }, "Device created");
  };

  const createClass = async (event) => {
    event.preventDefault();
    await msg.run(async () => {
      await api.createClass(cleanPayload(classForm));
      setClassForm(initialClass);
      await refresh();
    }, "Class created");
  };

  const enrollStudent = async (event) => {
    event.preventDefault();
    await msg.run(async () => {
      await api.addClassStudent(enrollForm.class_id, enrollForm.user_id);
      await refresh();
    }, "Student enrolled");
  };

  const createSession = async (event) => {
    event.preventDefault();
    await msg.run(async () => {
      await api.createSession(cleanPayload(sessionForm));
      setSessionForm(initialSession);
      await refresh();
    }, "Session created");
  };

  const toggleSession = async (session) => {
    await msg.run(async () => {
      await api.updateSession(session.id, { is_open: !session.is_open });
      await refresh();
    }, "Session updated");
  };

  const createBeacon = async (event) => {
    event.preventDefault();
    await msg.run(async () => {
      await api.createBeacon(cleanPayload(beaconForm));
      setBeaconForm(initialBeacon);
      await refresh();
    }, "Beacon created");
  };

  const loadAttendance = async (event) => {
    event?.preventDefault();
    await msg.run(async () => {
      const res = await api.attendance(cleanPayload(attendanceFilters));
      setAttendance(res.data);
    });
  };

  const updateAttendance = async (event) => {
    event.preventDefault();
    await msg.run(async () => {
      await api.updateAttendance(manualForm.attendance_id, cleanPayload({
        status: manualForm.status,
        note: manualForm.note,
        reason: manualForm.reason
      }));
      setManualForm({ attendance_id: "", status: "present", note: "", reason: "" });
      await refresh();
    }, "Attendance updated");
  };

  const loadReport = async (event) => {
    event.preventDefault();
    await msg.run(async () => {
      const [summaryRes, monthlyRes] = await Promise.all([
        api.reportSummary(month),
        api.reportMonthly(month)
      ]);
      setReport({ summary: summaryRes.data.summary, records: monthlyRes.data.records });
    });
  };

  const reviewAppeal = async (event) => {
    event.preventDefault();
    await msg.run(async () => {
      await api.reviewAppeal(appealReview.appeal_id, cleanPayload({
        status: appealReview.status,
        review_note: appealReview.review_note
      }));
      setAppealReview({ appeal_id: "", status: "approved", review_note: "" });
      await refresh();
    }, "Appeal reviewed");
  };

  if (!token) {
    return (
      <main className="login-page">
        <style>{styles}</style>
        <section className="login-panel">
          <h1>BLE Attendance Dashboard</h1>
          <p>Admin эсвэл teacher эрхээр нэвтэрч удирдлагын хэсгийг ашиглана.</p>
          <form onSubmit={submitLogin} className="stack">
            <TextInput value={username} onChange={setUsername} placeholder="Username" />
            <TextInput value={password} onChange={setPassword} placeholder="Password" type="password" />
            <button disabled={loading}>{loading ? "Logging in..." : "Login"}</button>
          </form>
          {msg.error && <p className="error">{msg.error}</p>}
        </section>
      </main>
    );
  }

  return (
    <main className="app-shell">
      <style>{styles}</style>
      <aside className="sidebar">
        <h1>BLE Attendance</h1>
        <p>{role || "user"}</p>
        <nav>
          {tabs.map(([id, label]) => (
            <button key={id} className={activeTab === id ? "active" : ""} onClick={() => setActiveTab(id)}>
              {label}
            </button>
          ))}
        </nav>
        <button className="secondary" onClick={signOut}>Logout</button>
      </aside>

      <section className="content">
        <header className="topbar">
          <div>
            <h2>{tabs.find(([id]) => id === activeTab)?.[1]}</h2>
            <p>{bootstrapped ? "Connected to backend API" : "Loading data..."}</p>
          </div>
          <div className="inline">
            <Field label="Month">
              <input type="month" value={month} onChange={(event) => setMonth(event.target.value)} />
            </Field>
            <button onClick={refresh} disabled={loading}>{loading ? "Refreshing..." : "Refresh"}</button>
          </div>
        </header>

        {msg.error && <div className="alert error">{msg.error}</div>}
        {msg.message && <div className="alert success">{msg.message}</div>}

        {activeTab === "overview" && (
          <div className="grid cards">
            <div className="metric"><span>Total</span><strong>{overview?.total_attendance ?? 0}</strong></div>
            <div className="metric"><span>Present</span><strong>{overview?.total_present ?? 0}</strong></div>
            <div className="metric"><span>Late</span><strong>{overview?.total_late ?? 0}</strong></div>
            <div className="metric"><span>Open sessions</span><strong>{overview?.open_sessions ?? 0}</strong></div>
          </div>
        )}

        {activeTab === "attendance" && (
          <div className="stack">
            <form className="panel form-grid" onSubmit={loadAttendance}>
              <Field label="User"><TextInput value={attendanceFilters.user_id} onChange={(v) => setAttendanceFilters({ ...attendanceFilters, user_id: v })} /></Field>
              <Field label="Session"><TextInput value={attendanceFilters.session_id} onChange={(v) => setAttendanceFilters({ ...attendanceFilters, session_id: v })} /></Field>
              <Field label="Class"><TextInput value={attendanceFilters.class_id} onChange={(v) => setAttendanceFilters({ ...attendanceFilters, class_id: v })} /></Field>
              <Field label="Status">
                <select value={attendanceFilters.status} onChange={(e) => setAttendanceFilters({ ...attendanceFilters, status: e.target.value })}>
                  <option value="">All</option><option value="present">present</option><option value="late">late</option><option value="checked_out">checked_out</option><option value="absent">absent</option>
                </select>
              </Field>
              <button>Apply filters</button>
            </form>
            <form className="panel form-grid" onSubmit={updateAttendance}>
              <Field label="Attendance ID"><TextInput value={manualForm.attendance_id} onChange={(v) => setManualForm({ ...manualForm, attendance_id: v })} /></Field>
              <Field label="Status">
                <select value={manualForm.status} onChange={(e) => setManualForm({ ...manualForm, status: e.target.value })}>
                  <option value="present">present</option><option value="late">late</option><option value="checked_out">checked_out</option><option value="absent">absent</option>
                </select>
              </Field>
              <Field label="Note"><TextInput value={manualForm.note} onChange={(v) => setManualForm({ ...manualForm, note: v })} /></Field>
              <Field label="Reason"><TextInput value={manualForm.reason} onChange={(v) => setManualForm({ ...manualForm, reason: v })} /></Field>
              <button>Manual update</button>
            </form>
            <Table columns={[
              { key: "id", label: "ID" },
              { key: "user_id", label: "User" },
              { key: "session_id", label: "Session" },
              { key: "status", label: "Status", render: (r) => <Status value={r.status} /> },
              { key: "late_minutes", label: "Late min" },
              { key: "distance_m", label: "Distance" },
              { key: "check_in_time", label: "Check-in" }
            ]} rows={attendance} />
          </div>
        )}

        {activeTab === "users" && (
          <div className="stack">
            <form className="panel form-grid" onSubmit={createUser}>
              {["id", "username", "full_name", "email", "phone", "password"].map((key) => (
                <Field key={key} label={key}><TextInput value={userForm[key]} onChange={(v) => setUserForm({ ...userForm, [key]: v })} type={key === "password" ? "password" : "text"} /></Field>
              ))}
              <Field label="Role">
                <select value={userForm.role} onChange={(e) => setUserForm({ ...userForm, role: e.target.value })}>
                  <option value="student">student</option><option value="teacher">teacher</option><option value="admin">admin</option>
                </select>
              </Field>
              <button>Create user</button>
            </form>
            <form className="panel form-grid" onSubmit={createDevice}>
              <Field label="User ID"><TextInput value={deviceForm.user_id} onChange={(v) => setDeviceForm({ ...deviceForm, user_id: v, uuid: deviceForm.uuid || `DEVICE_${v}` })} /></Field>
              <Field label="Device UUID"><TextInput value={deviceForm.uuid} onChange={(v) => setDeviceForm({ ...deviceForm, uuid: v })} /></Field>
              <Field label="Name"><TextInput value={deviceForm.name} onChange={(v) => setDeviceForm({ ...deviceForm, name: v })} /></Field>
              <Field label="Platform"><TextInput value={deviceForm.platform} onChange={(v) => setDeviceForm({ ...deviceForm, platform: v })} /></Field>
              <button>Create device</button>
            </form>
            <Table columns={[
              { key: "id", label: "ID" },
              { key: "username", label: "Username" },
              { key: "full_name", label: "Name" },
              { key: "role", label: "Role" },
              { key: "is_active", label: "Active", render: (r) => String(r.is_active) },
              { key: "action", label: "Action", render: (r) => <button onClick={() => toggleUser(r)}>{r.is_active ? "Deactivate" : "Activate"}</button> }
            ]} rows={users} />
            <Table columns={[
              { key: "id", label: "ID" },
              { key: "user_id", label: "User" },
              { key: "uuid", label: "UUID" },
              { key: "platform", label: "Platform" },
              { key: "is_active", label: "Active", render: (r) => String(r.is_active) }
            ]} rows={devices} />
          </div>
        )}

        {activeTab === "classes" && (
          <div className="stack">
            <form className="panel form-grid" onSubmit={createClass}>
              {["id", "name", "code", "day_of_week", "start_time", "end_time"].map((key) => (
                <Field key={key} label={key}><TextInput value={classForm[key]} onChange={(v) => setClassForm({ ...classForm, [key]: v })} /></Field>
              ))}
              <Field label="Teacher">
                <select value={classForm.teacher_id} onChange={(e) => setClassForm({ ...classForm, teacher_id: e.target.value })}>
                  <option value="">None</option>{teacherUsers.map((u) => <option key={u.id} value={u.id}>{u.full_name}</option>)}
                </select>
              </Field>
              <Field label="Room">
                <select value={classForm.room_id} onChange={(e) => setClassForm({ ...classForm, room_id: e.target.value })}>
                  <option value="">None</option>{rooms.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
                </select>
              </Field>
              <Field label="Beacon">
                <select value={classForm.beacon_id} onChange={(e) => setClassForm({ ...classForm, beacon_id: e.target.value })}>
                  <option value="">None</option>{beacons.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
                </select>
              </Field>
              <button>Create class</button>
            </form>
            <form className="panel form-grid" onSubmit={enrollStudent}>
              <Field label="Class">
                <select value={enrollForm.class_id} onChange={(e) => setEnrollForm({ ...enrollForm, class_id: e.target.value })}>
                  <option value="">Choose class</option>{classes.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
                </select>
              </Field>
              <Field label="Student">
                <select value={enrollForm.user_id} onChange={(e) => setEnrollForm({ ...enrollForm, user_id: e.target.value })}>
                  <option value="">Choose student</option>{studentUsers.map((u) => <option key={u.id} value={u.id}>{u.full_name}</option>)}
                </select>
              </Field>
              <button>Enroll student</button>
            </form>
            <Table columns={[
              { key: "id", label: "ID" },
              { key: "name", label: "Name" },
              { key: "teacher_id", label: "Teacher" },
              { key: "room_id", label: "Room" },
              { key: "beacon_id", label: "Beacon" },
              { key: "start_time", label: "Start" },
              { key: "end_time", label: "End" }
            ]} rows={classes} />
          </div>
        )}

        {activeTab === "sessions" && (
          <div className="stack">
            <form className="panel form-grid" onSubmit={createSession}>
              <Field label="ID"><TextInput value={sessionForm.id} onChange={(v) => setSessionForm({ ...sessionForm, id: v })} /></Field>
              <Field label="Class">
                <select value={sessionForm.class_or_shift_id} onChange={(e) => setSessionForm({ ...sessionForm, class_or_shift_id: e.target.value })}>
                  <option value="">Choose class</option>{classes.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
                </select>
              </Field>
              <Field label="Beacon">
                <select value={sessionForm.beacon_id} onChange={(e) => setSessionForm({ ...sessionForm, beacon_id: e.target.value })}>
                  <option value="">None</option>{beacons.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
                </select>
              </Field>
              <Field label="Date"><TextInput value={sessionForm.session_date} onChange={(v) => setSessionForm({ ...sessionForm, session_date: v })} type="date" /></Field>
              <Field label="Start"><TextInput value={sessionForm.start_time} onChange={(v) => setSessionForm({ ...sessionForm, start_time: v })} /></Field>
              <Field label="End"><TextInput value={sessionForm.end_time} onChange={(v) => setSessionForm({ ...sessionForm, end_time: v })} /></Field>
              <button>Create session</button>
            </form>
            <form className="panel form-grid" onSubmit={createBeacon}>
              {["id", "uuid", "name", "major", "minor"].map((key) => (
                <Field key={key} label={`Beacon ${key}`}><TextInput value={beaconForm[key]} onChange={(v) => setBeaconForm({ ...beaconForm, [key]: v })} /></Field>
              ))}
              <Field label="Room">
                <select value={beaconForm.room_id} onChange={(e) => setBeaconForm({ ...beaconForm, room_id: e.target.value })}>
                  <option value="">None</option>{rooms.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
                </select>
              </Field>
              <button>Create beacon</button>
            </form>
            <Table columns={[
              { key: "id", label: "ID" },
              { key: "class_or_shift_id", label: "Class" },
              { key: "session_date", label: "Date" },
              { key: "is_open", label: "Open", render: (r) => String(r.is_open) },
              { key: "action", label: "Action", render: (r) => <button onClick={() => toggleSession(r)}>{r.is_open ? "Close" : "Open"}</button> }
            ]} rows={sessions} />
          </div>
        )}

        {activeTab === "reports" && (
          <div className="stack">
            <form className="panel inline" onSubmit={loadReport}>
              <button>Load report</button>
              <a className="button-link" href={api.reportDownloadUrl("excel", month)}>Excel</a>
              <a className="button-link" href={api.reportDownloadUrl("pdf", month)}>PDF</a>
            </form>
            <div className="grid cards">
              {(report?.summary || []).map((item) => (
                <div className="metric" key={item.status}><span>{item.status}</span><strong>{item.count}</strong></div>
              ))}
            </div>
            <Table columns={[
              { key: "id", label: "ID" },
              { key: "user_id", label: "User" },
              { key: "session_id", label: "Session" },
              { key: "date", label: "Date" },
              { key: "status", label: "Status", render: (r) => <Status value={r.status} /> },
              { key: "late_minutes", label: "Late min" }
            ]} rows={report?.records || []} />
          </div>
        )}

        {activeTab === "appeals" && (
          <div className="stack">
            <form className="panel form-grid" onSubmit={reviewAppeal}>
              <Field label="Appeal ID"><TextInput value={appealReview.appeal_id} onChange={(v) => setAppealReview({ ...appealReview, appeal_id: v })} /></Field>
              <Field label="Status">
                <select value={appealReview.status} onChange={(e) => setAppealReview({ ...appealReview, status: e.target.value })}>
                  <option value="approved">approved</option><option value="rejected">rejected</option>
                </select>
              </Field>
              <Field label="Review note"><TextInput value={appealReview.review_note} onChange={(v) => setAppealReview({ ...appealReview, review_note: v })} /></Field>
              <button>Review appeal</button>
            </form>
            <Table columns={[
              { key: "id", label: "ID" },
              { key: "user_id", label: "User" },
              { key: "session_id", label: "Session" },
              { key: "reason_type", label: "Reason" },
              { key: "message", label: "Message" },
              { key: "status", label: "Status", render: (r) => <Status value={r.status} /> }
            ]} rows={appeals} />
          </div>
        )}

        {activeTab === "audit" && (
          <Table columns={[
            { key: "id", label: "ID" },
            { key: "actor_user_id", label: "Actor" },
            { key: "action", label: "Action" },
            { key: "entity_type", label: "Entity" },
            { key: "reason", label: "Reason" },
            { key: "created_at", label: "Created" }
          ]} rows={auditLogs} />
        )}
      </section>
    </main>
  );
}

const styles = `
* { box-sizing: border-box; }
body { margin: 0; background: #f6f7f9; color: #17202a; font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
button, .button-link { border: 0; background: #1f6feb; color: white; padding: 10px 14px; border-radius: 8px; cursor: pointer; font-weight: 700; text-decoration: none; display: inline-flex; align-items: center; justify-content: center; min-height: 38px; }
button.secondary { background: #334155; }
button:disabled { opacity: 0.55; cursor: not-allowed; }
input, select { width: 100%; border: 1px solid #cbd5e1; border-radius: 8px; padding: 10px; background: white; color: #17202a; min-height: 38px; }
.login-page { min-height: 100vh; display: grid; place-items: center; padding: 24px; }
.login-panel { width: min(440px, 100%); background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 28px; box-shadow: 0 18px 40px rgba(15, 23, 42, 0.08); }
.app-shell { min-height: 100vh; display: grid; grid-template-columns: 250px 1fr; }
.sidebar { background: #111827; color: white; padding: 22px; display: flex; flex-direction: column; gap: 18px; }
.sidebar h1 { font-size: 22px; margin: 0; }
.sidebar p { color: #cbd5e1; margin: 0; }
.sidebar nav { display: grid; gap: 8px; }
.sidebar nav button { justify-content: flex-start; background: transparent; color: #d1d5db; }
.sidebar nav button.active { background: #2563eb; color: white; }
.content { padding: 24px; overflow: auto; }
.topbar { display: flex; justify-content: space-between; gap: 16px; align-items: flex-start; margin-bottom: 20px; }
.topbar h2 { margin: 0 0 4px; font-size: 28px; }
.topbar p { margin: 0; color: #64748b; }
.stack { display: grid; gap: 16px; }
.inline { display: flex; gap: 10px; align-items: end; flex-wrap: wrap; }
.grid { display: grid; gap: 16px; }
.cards { grid-template-columns: repeat(4, minmax(160px, 1fr)); }
.metric, .panel, .table-wrap { background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px; }
.metric span { color: #64748b; display: block; font-size: 13px; }
.metric strong { font-size: 32px; display: block; margin-top: 8px; }
.form-grid { display: grid; grid-template-columns: repeat(4, minmax(160px, 1fr)); gap: 12px; align-items: end; }
.field { display: grid; gap: 6px; font-size: 13px; color: #475569; }
.table-wrap { overflow: auto; padding: 0; }
table { width: 100%; border-collapse: collapse; min-width: 760px; }
th, td { border-bottom: 1px solid #e2e8f0; padding: 11px 12px; text-align: left; font-size: 13px; vertical-align: top; }
th { background: #f8fafc; color: #475569; position: sticky; top: 0; }
.empty { text-align: center; color: #64748b; padding: 28px; }
.badge { display: inline-flex; border-radius: 999px; padding: 4px 9px; background: #e2e8f0; font-weight: 700; font-size: 12px; }
.badge-present, .badge-approved { background: #dcfce7; color: #166534; }
.badge-late, .badge-pending { background: #fef3c7; color: #92400e; }
.badge-checked_out { background: #dbeafe; color: #1e40af; }
.badge-rejected, .badge-absent { background: #fee2e2; color: #991b1b; }
.alert { padding: 12px 14px; border-radius: 8px; margin-bottom: 16px; }
.error { color: #991b1b; background: #fee2e2; }
.success { color: #166534; background: #dcfce7; }
@media (max-width: 980px) {
  .app-shell { grid-template-columns: 1fr; }
  .sidebar { position: static; }
  .cards, .form-grid { grid-template-columns: 1fr; }
  .topbar { flex-direction: column; }
}
`;
