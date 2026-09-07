// In the browser (dev or a normal web deploy) '/api' is same-origin and works via the vite proxy
// or a reverse proxy in front of the built site. Inside the Capacitor Android shell the app runs
// from a file://-ish origin with no proxy, so VITE_API_BASE_URL must be set at build time to the
// deployed backend's absolute URL (see README "Building the Android app").
const API_BASE = import.meta.env.VITE_API_BASE_URL || '/api';

export interface Session {
  token: string;
  role: 'member_primary' | 'member_dependent' | 'provider_doctor' | 'provider_clinic_admin' | 'platform_admin';
  displayName: string;
  memberId: string | null;
  familyId: string | null;
  providerId: string | null;
}

const TOKEN_KEY = 'careloop_token';

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}
export function setToken(token: string | null) {
  if (token) localStorage.setItem(TOKEN_KEY, token);
  else localStorage.removeItem(TOKEN_KEY);
}

class ApiError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

async function request<T>(method: string, path: string, body?: unknown, isForm = false): Promise<T> {
  const headers: Record<string, string> = {};
  const token = getToken();
  if (token) headers['Authorization'] = `Bearer ${token}`;
  if (!isForm && body !== undefined) headers['Content-Type'] = 'application/json';

  const resp = await fetch(`${API_BASE}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : isForm ? (body as FormData) : JSON.stringify(body),
  });

  if (resp.status === 204) return undefined as T;
  const data = await resp.json().catch(() => null);
  if (!resp.ok) {
    throw new ApiError(data?.error || `Request failed (${resp.status})`, resp.status);
  }
  return data as T;
}

export const api = {
  login: (email: string, password: string) => request<Session>('POST', '/login', { email, password }),
  me: () => request<Session>('GET', '/me'),

  getFamily: () => request<{ familyId: string; members: any[] }>('GET', '/family'),
  addMember: (payload: any) => request<{ id: string }>('POST', '/family/members', payload),
  getSummary: (memberId: string) => request<any>('GET', `/members/${memberId}/summary`),
  addAllergy: (memberId: string, value: string) => request('POST', `/members/${memberId}/allergies`, { value }),
  addChronicCondition: (memberId: string, value: string) => request('POST', `/members/${memberId}/chronic-conditions`, { value }),

  getDocuments: (memberId: string) => request<any[]>('GET', `/documents?member_id=${memberId}`),
  getDocument: (id: string) => request<any>('GET', `/documents/${id}`),
  uploadDocument: (form: FormData) => request<any>('POST', '/documents', form, true),

  getTrends: (memberId: string) => request<any>('GET', `/parameters/trends?member_id=${memberId}`),
  getYoY: (memberId: string, date1?: string, date2?: string) =>
    request<any>('GET', `/parameters/yoy?member_id=${memberId}${date1 ? `&date1=${date1}&date2=${date2}` : ''}`),
  getReviewQueue: (memberId: string) => request<any[]>('GET', `/parameters/review-queue?member_id=${memberId}`),
  confirmParameter: (id: string) => request('POST', `/parameters/${id}/confirm`),
  correctParameter: (id: string, payload: any) => request('POST', `/parameters/${id}/correct`, payload),
  rejectParameter: (id: string) => request('POST', `/parameters/${id}/reject`),

  getPrescriptions: (memberId: string) => request<any[]>('GET', `/prescriptions?member_id=${memberId}`),
  getAudit: (memberId: string) => request<any[]>('GET', `/audit?member_id=${memberId}`),

  getProviders: () => request<any[]>('GET', '/providers'),
  getAppointments: () => request<any[]>('GET', '/appointments'),
  getAppointment: (id: string) => request<any>('GET', `/appointments/${id}`),
  bookAppointment: (payload: any) => request<{ id: string }>('POST', '/appointments', payload),
  checkIn: (id: string) => request('POST', `/appointments/${id}/check-in`, {}),
  requestConsent: (id: string, method: 'in_app' | 'otp') => request<{ otp?: string; expiresAt: string }>('POST', `/appointments/${id}/request-consent`, { method }),
  resendConsent: (id: string, method: 'in_app' | 'otp') => request<{ otp?: string; expiresAt: string }>('POST', `/appointments/${id}/resend-consent`, { method }),
  respondConsent: (id: string, approve: boolean) => request('POST', `/appointments/${id}/respond-consent`, { approve }),
  verifyOtp: (id: string, otp: string) => request('POST', `/appointments/${id}/verify-otp`, { otp }),
  startConsultation: (id: string) => request('POST', `/appointments/${id}/start-consultation`, {}),
  issuePrescription: (id: string, payload: any) => request<{ prescriptionId: string }>('POST', `/appointments/${id}/prescriptions`, payload),
  completeVisit: (id: string) => request('POST', `/appointments/${id}/complete`, {}),

  getCandidates: (status = 'pending') => request<any[]>('GET', `/admin/candidates?status=${status}`),
  resolveCandidate: (id: string, payload: any) => request('POST', `/admin/candidates/${id}/resolve`, payload),
  getAdminReviewQueue: () => request<any[]>('GET', '/admin/review-queue'),
};

export { ApiError };
