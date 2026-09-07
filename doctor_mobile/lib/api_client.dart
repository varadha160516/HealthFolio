import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Same backend CareLoop/HealthFolio already runs — this app is a separate client against the
/// exact same API, not a fork. Overridden at build time via:
///   flutter build apk --dart-define=API_BASE_URL=https://your-server.example.com/api
const String apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:4000/api');

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, this.status);
  @override
  String toString() => message;
}

class Session {
  final String token;
  final String role;
  final String displayName;
  final String? providerId;
  Session({required this.token, required this.role, required this.displayName, this.providerId});

  factory Session.fromJson(Map<String, dynamic> j) => Session(token: j['token'], role: j['role'], displayName: j['displayName'], providerId: j['providerId']);

  bool get isProvider => role == 'provider_doctor' || role == 'provider_clinic_admin';
}

class ApiClient {
  String? _token;

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('doctor_console_token');
  }

  Future<void> setToken(String? token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove('doctor_console_token');
    } else {
      await prefs.setString('doctor_console_token', token);
    }
  }

  String? get token => _token;

  Map<String, String> get _headers => {'Content-Type': 'application/json', if (_token != null) 'Authorization': 'Bearer $_token'};

  Future<dynamic> _get(String path) async => _handle(await http.get(Uri.parse('$apiBaseUrl$path'), headers: _headers));
  Future<dynamic> _post(String path, [Map<String, dynamic>? body]) async =>
      _handle(await http.post(Uri.parse('$apiBaseUrl$path'), headers: _headers, body: body == null ? null : jsonEncode(body)));
  Future<dynamic> _put(String path, Map<String, dynamic> body) async => _handle(await http.put(Uri.parse('$apiBaseUrl$path'), headers: _headers, body: jsonEncode(body)));

  dynamic _handle(http.Response resp) {
    if (resp.statusCode == 204 || resp.body.isEmpty) return null;
    dynamic decoded;
    try {
      decoded = jsonDecode(resp.body);
    } on FormatException {
      throw ApiException('Could not reach the server — check your connection and try again.', resp.statusCode);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(decoded is Map ? (decoded['error'] ?? 'Request failed') : 'Request failed (${resp.statusCode})', resp.statusCode);
    }
    return decoded;
  }

  // --- Auth ---
  Future<Session> login(String email, String password) async => Session.fromJson(await _post('/login', {'email': email, 'password': password}));
  Future<Session> me() async => Session.fromJson(await _get('/me'));

  // --- Appointments (shared with the web provider console) ---
  Future<List<dynamic>> getAppointments() async => await _get('/appointments');
  Future<Map<String, dynamic>> getAppointment(String id) async => await _get('/appointments/$id');
  Future<void> checkIn(String id) => _post('/appointments/$id/check-in');
  Future<Map<String, dynamic>> requestConsent(String id, String method) async => await _post('/appointments/$id/request-consent', {'method': method});
  Future<Map<String, dynamic>> resendConsent(String id, String method) async => await _post('/appointments/$id/resend-consent', {'method': method});
  Future<void> verifyOtp(String id, String otp) => _post('/appointments/$id/verify-otp', {'otp': otp});
  Future<void> startConsultation(String id) => _post('/appointments/$id/start-consultation');
  Future<void> completeVisit(String id) => _post('/appointments/$id/complete');
  Future<Map<String, dynamic>> getPrevisitBrief(String id) async => await _get('/appointments/$id/previsit-brief');

  // --- Vitals ---
  Future<void> addVitals(String appointmentId, Map<String, dynamic> fields) => _post('/appointments/$appointmentId/vitals', fields);
  Future<List<dynamic>> getVitals(String appointmentId) async => (await _get('/appointments/$appointmentId/vitals') as Map<String, dynamic>)['entries'] as List<dynamic>;

  // --- Consultation notes (symptoms, examination, assessment, advice, follow-up preference) ---
  Future<Map<String, dynamic>?> getConsultationNotes(String appointmentId) async => await _get('/appointments/$appointmentId/consultation-notes') as Map<String, dynamic>?;
  Future<Map<String, dynamic>> saveConsultationNotes(String appointmentId, Map<String, dynamic> payload) async =>
      await _put('/appointments/$appointmentId/consultation-notes', payload);

  // --- Diagnosis + medications (issued as a prescription, same record the member sees) ---
  Future<void> issuePrescription(String appointmentId, {String? diagnosisText, String? icdCode, String? notes, required List<Map<String, dynamic>> lineItems}) =>
      _post('/appointments/$appointmentId/prescriptions', {'diagnosis_text': diagnosisText, 'icd_code': icdCode, 'notes': notes, 'line_items': lineItems});

  // --- Lab orders ---
  Future<void> orderLabTests(String appointmentId, {required List<String> testNames, String? labName, String? clinicalIndication}) =>
      _post('/appointments/$appointmentId/lab-orders', {'test_names': testNames, 'lab_name': labName, 'clinical_indication': clinicalIndication});
  Future<List<dynamic>> getLabOrders(String appointmentId) async => await _get('/appointments/$appointmentId/lab-orders');
  // Full test catalog (same one the member app's own lab-booking flow reads from) — used to back
  // the searchable "Select lab tests" sheet instead of a fixed short chip list.
  Future<List<dynamic>> getLabTestCatalog() async => await _get('/lab-tests/catalog');

  // --- Follow-up ---
  Future<Map<String, dynamic>> scheduleFollowUp(String appointmentId, {required String after, String? reason}) async =>
      await _post('/appointments/$appointmentId/schedule-follow-up', {'after': after, 'reason': reason});

  // --- Visit summary / patient history ---
  Future<Map<String, dynamic>> getVisitSummary(String appointmentId) async => await _get('/appointments/$appointmentId/visit-summary');
  Future<List<dynamic>> getPatientVisitHistory(String appointmentId) async => await _get('/appointments/$appointmentId/patient-visit-history');

  // --- Doctor's patient list ---
  Future<List<dynamic>> getMyPatients() async => await _get('/providers/me/patients');
  Future<Map<String, dynamic>> getMyPatient(String memberId) async => await _get('/providers/me/patients/$memberId');

  // --- Notifications ---
  Future<List<dynamic>> getNotifications() async => await _get('/providers/me/notifications');
  Future<void> markNotificationRead(String id) => _post('/providers/me/notifications/$id/read');
}
