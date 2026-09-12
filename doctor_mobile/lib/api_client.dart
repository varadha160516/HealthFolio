import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
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
  Future<dynamic> _patch(String path, Map<String, dynamic> body) async => _handle(await http.patch(Uri.parse('$apiBaseUrl$path'), headers: _headers, body: jsonEncode(body)));
  Future<dynamic> _delete(String path) async => _handle(await http.delete(Uri.parse('$apiBaseUrl$path'), headers: _headers));

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
  Future<void> completeVisit(String id, {required double feeAmount}) => _post('/appointments/$id/complete', {'fee_amount': feeAmount});
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

  // --- Referrals ---
  Future<Map<String, dynamic>> createReferral(
    String appointmentId, {
    String? targetSpecialty,
    String? targetProviderId,
    required String reason,
    String? notes,
    String urgency = 'routine',
  }) async =>
      await _post('/appointments/$appointmentId/referrals', {
        'target_specialty': targetSpecialty,
        'target_provider_id': targetProviderId,
        'reason': reason,
        'notes': notes,
        'urgency': urgency,
      });
  Future<List<dynamic>> getReferrals(String appointmentId) async => await _get('/appointments/$appointmentId/referrals');
  Future<List<dynamic>> searchProviders(String query) async => await _get('/providers/search?q=${Uri.encodeQueryComponent(query)}');

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

  // --- Practice settings: default fee, working hours, time off ---
  Future<Map<String, dynamic>> getMyProfile() async => await _get('/providers/me/profile');
  Future<void> updateDefaultFee(double fee) => _patch('/providers/me/profile', {'default_fee': fee});
  Future<void> updateCredentials({String? registrationNumber, String? qualifications, int? yearsOfExperience}) => _patch('/providers/me/profile', {
        'registration_number': registrationNumber,
        'qualifications': qualifications,
        'years_of_experience': yearsOfExperience,
      });

  Future<List<dynamic>> getAvailability() async => await _get('/providers/me/availability');
  Future<void> addAvailability({required int dayOfWeek, required String startTime, required String endTime}) =>
      _post('/providers/me/availability', {'day_of_week': dayOfWeek, 'start_time': startTime, 'end_time': endTime});
  Future<void> deleteAvailability(String id) => _delete('/providers/me/availability/$id');

  Future<List<dynamic>> getTimeOff() async => await _get('/providers/me/time-off');
  Future<void> addTimeOff({required String date, String? reason}) => _post('/providers/me/time-off', {'date': date, 'reason': reason});
  Future<void> deleteTimeOff(String id) => _delete('/providers/me/time-off/$id');

  // --- Billing ---
  Future<List<dynamic>> getMyInvoices({String? query, String? from, String? to}) async {
    final params = <String, String>{};
    if (query != null && query.isNotEmpty) params['q'] = query;
    if (from != null) params['from'] = from;
    if (to != null) params['to'] = to;
    final qs = params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
    return await _get('/providers/me/invoices$qs');
  }

  // --- Profile extras: GST, signature, payout details ---
  Future<void> updateGstNumber(String gst) => _patch('/providers/me/profile', {'gst_number': gst});
  Future<void> updateSignature(String base64Png) => _patch('/providers/me/profile', {'signature_base64': base64Png});
  Future<void> updateBankDetails({String? accountName, String? accountNumber, String? ifsc, String? upiId}) => _patch('/providers/me/profile', {
        'bank_account_name': accountName,
        'bank_account_number': accountNumber,
        'bank_ifsc': ifsc,
        'bank_upi_id': upiId,
      });

  // --- Clinic ---
  Future<Map<String, dynamic>> getMyClinic() async => await _get('/clinics/me');
  Future<void> updateClinic(Map<String, dynamic> payload) => _patch('/clinics/me', payload);
  Future<List<dynamic>> getClinicProviders() async => await _get('/clinics/me/providers');

  // --- Practice templates ---
  Future<List<dynamic>> getPrescriptionTemplates() async => await _get('/providers/me/prescription-templates');
  Future<Map<String, dynamic>> addPrescriptionTemplate(Map<String, dynamic> payload) async => await _post('/providers/me/prescription-templates', payload);
  Future<void> deletePrescriptionTemplate(String id) => _delete('/providers/me/prescription-templates/$id');

  Future<List<dynamic>> getLabTestPanels() async => await _get('/providers/me/lab-test-panels');
  Future<Map<String, dynamic>> addLabTestPanel(Map<String, dynamic> payload) async => await _post('/providers/me/lab-test-panels', payload);
  Future<void> deleteLabTestPanel(String id) => _delete('/providers/me/lab-test-panels/$id');

  // --- Analytics ---
  Future<Map<String, dynamic>> getAnalytics() async => await _get('/providers/me/analytics');

  // --- Compliance ---
  Future<List<dynamic>> getMyAuditLog() async => await _get('/providers/me/audit-log');

  // --- Provider onboarding (public — no session exists yet for an applicant) ---
  Future<List<dynamic>> getPublicSpecializations() async => await _get('/public/specializations');
  Future<List<dynamic>> getPublicClinics() async => await _get('/public/clinics');

  Future<Map<String, dynamic>> submitProviderApplication(Map<String, dynamic> fields, List<ApplicationFile> files) async {
    final req = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/provider-applications'));
    _fillApplicationRequest(req, fields, files);
    final resp = await http.Response.fromStream(await req.send());
    return _handle(resp) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> resubmitProviderApplication(String applicationId, Map<String, dynamic> fields, List<ApplicationFile> files) async {
    final req = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/provider-applications/$applicationId/resubmit'));
    _fillApplicationRequest(req, fields, files);
    final resp = await http.Response.fromStream(await req.send());
    return (_handle(resp) as Map<String, dynamic>?) ?? {};
  }

  void _fillApplicationRequest(http.MultipartRequest req, Map<String, dynamic> fields, List<ApplicationFile> files) {
    fields.forEach((k, v) {
      if (v != null) req.fields[k] = '$v';
    });
    if (files.isNotEmpty) req.fields['document_types'] = jsonEncode(files.map((f) => f.documentType).toList());
    for (final f in files) {
      req.files.add(http.MultipartFile.fromBytes('documents', f.bytes, filename: f.filename, contentType: _mediaTypeForFilename(f.filename)));
    }
  }

  Future<Map<String, dynamic>> getApplicationStatus({required String email, required String referenceCode}) async =>
      await _get('/provider-applications/status?email=${Uri.encodeQueryComponent(email)}&reference_code=${Uri.encodeQueryComponent(referenceCode)}');

  // --- Admin: provider onboarding review queue ---
  Future<List<dynamic>> getProviderApplications({String? status}) async => await _get('/admin/provider-applications${status != null ? '?status=$status' : ''}');
  Future<Map<String, dynamic>> getProviderApplicationDetail(String id) async => await _get('/admin/provider-applications/$id');
  Future<Uint8List> getApplicationDocumentBytes(String applicationId, String documentId) async {
    final resp = await http.get(Uri.parse('$apiBaseUrl/admin/provider-applications/$applicationId/documents/$documentId/file'), headers: _headers);
    if (resp.statusCode < 200 || resp.statusCode >= 300) throw ApiException('Could not load this document (${resp.statusCode})', resp.statusCode);
    return resp.bodyBytes;
  }

  Future<Map<String, dynamic>> approveProviderApplication(String id) async => await _post('/admin/provider-applications/$id/approve');
  Future<void> rejectProviderApplication(String id, String reason) => _post('/admin/provider-applications/$id/reject', {'reason': reason});
}

MediaType _mediaTypeForFilename(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return MediaType('image', 'png');
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return MediaType('image', 'jpeg');
  if (lower.endsWith('.webp')) return MediaType('image', 'webp');
  if (lower.endsWith('.pdf')) return MediaType('application', 'pdf');
  return MediaType('application', 'octet-stream');
}

/// One document picked for a provider application — `documentType` matches the server's
/// `provider_application_documents.document_type` enum (registration_certificate, government_id,
/// qualification_certificate, clinic_proof, other).
class ApplicationFile {
  final String documentType;
  final String filename;
  final List<int> bytes;
  ApplicationFile({required this.documentType, required this.filename, required this.bytes});
}
