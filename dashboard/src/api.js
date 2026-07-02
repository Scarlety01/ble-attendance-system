import axios from "axios";

const API = import.meta.env.VITE_API_BASE_URL || "http://127.0.0.1:8000";

const client = axios.create({
  baseURL: API,
  headers: {
    "Content-Type": "application/json",
    Accept: "application/json"
  }
});

client.interceptors.request.use((config) => {
  const token = localStorage.getItem("access_token");
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

export const login = async ({ username, password }) => {
  const res = await client.post("/auth/login", { username, password });
  localStorage.setItem("access_token", res.data.access_token);
  localStorage.setItem("role", res.data.role);
  localStorage.setItem("user_id", res.data.user_id);
  return res;
};

export const logout = () => {
  localStorage.removeItem("access_token");
  localStorage.removeItem("role");
  localStorage.removeItem("user_id");
};

export const getAttendance = async () => {
  return client.get("/attendance/all");
};

export const api = {
  overview: (month) => client.get("/dashboard/overview", { params: { month } }),
  users: () => client.get("/users"),
  createUser: (payload) => client.post("/users", payload),
  updateUser: (id, payload) => client.patch(`/users/${id}`, payload),
  devices: () => client.get("/devices"),
  createDevice: (payload) => client.post("/devices", payload),
  rooms: () => client.get("/rooms"),
  beacons: () => client.get("/beacons"),
  createBeacon: (payload) => client.post("/beacons", payload),
  classes: () => client.get("/classes"),
  createClass: (payload) => client.post("/classes", payload),
  updateClass: (id, payload) => client.patch(`/classes/${id}`, payload),
  classStudents: (classId) => client.get(`/classes/${classId}/students`),
  addClassStudent: (classId, userId) => client.post(`/classes/${classId}/students`, { user_id: userId }),
  removeClassStudent: (classId, userId) => client.delete(`/classes/${classId}/students/${userId}`),
  sessions: () => client.get("/sessions"),
  createSession: (payload) => client.post("/sessions", payload),
  updateSession: (id, payload) => client.patch(`/sessions/${id}`, payload),
  attendance: (params) => client.get("/attendance/all", { params }),
  updateAttendance: (id, payload) => client.patch(`/attendance/${id}/manual-update`, payload),
  reportSummary: (month, params) => client.get(`/report/summary/${month}`, { params }),
  reportMonthly: (month, params) => client.get(`/report/monthly/${month}`, { params }),
  reportDownloadUrl: (kind, month, params = {}) => {
    const url = new URL(`${API}/report/${kind}/${month}`);
    Object.entries(params).forEach(([key, value]) => {
      if (value !== undefined && value !== null && value !== "") {
        url.searchParams.set(key, value);
      }
    });
    return url.toString();
  },
  appeals: (params) => client.get("/attendance/appeals", { params }),
  reviewAppeal: (id, payload) => client.patch(`/attendance/appeals/${id}/review`, payload),
  auditLogs: () => client.get("/audit-logs")
};
