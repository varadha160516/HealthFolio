import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// package:http's MultipartFile defaults to application/octet-stream when no contentType is
/// given, which Claude's vision API rejects outright — it only accepts jpeg/png/webp/gif/pdf.
/// Derive the real type from the filename extension so the server (and Claude) get a type they
/// can actually use.
MediaType _mediaTypeForFilename(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return MediaType('image', 'png');
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return MediaType('image', 'jpeg');
  if (lower.endsWith('.webp')) return MediaType('image', 'webp');
  if (lower.endsWith('.gif')) return MediaType('image', 'gif');
  if (lower.endsWith('.pdf')) return MediaType('application', 'pdf');
  return MediaType('application', 'octet-stream');
}

/// Base URL for the CareLoop backend. Overridden at build time via:
///   flutter build apk --dart-define=API_BASE_URL=https://your-server.example.com/api
/// Defaults to the Android emulator's alias for the host machine's localhost, so a debug
/// build talks to `npm run dev:server` running on your dev machine out of the box.
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
  final String? memberId;
  final String? familyId;
  final String? providerId;

  Session({required this.token, required this.role, required this.displayName, this.memberId, this.familyId, this.providerId});

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        token: j['token'],
        role: j['role'],
        displayName: j['displayName'],
        memberId: j['memberId'],
        familyId: j['familyId'],
        providerId: j['providerId'],
      );

  bool get isMember => role == 'member_primary' || role == 'member_dependent';
  bool get isProvider => role == 'provider_doctor' || role == 'provider_clinic_admin';
  bool get isAdmin => role == 'platform_admin';
}

/// Thin REST client mirroring web/src/api/client.ts method-for-method, so the two clients
/// stay obviously in sync with the same backend contract.
class ApiClient {
  String? _token;

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('careloop_token');
  }

  Future<void> setToken(String? token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove('careloop_token');
    } else {
      await prefs.setString('careloop_token', token);
    }
  }

  String? get token => _token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<dynamic> _get(String path) async {
    final resp = await http.get(Uri.parse('$apiBaseUrl$path'), headers: _headers);
    return _handle(resp);
  }

  Future<dynamic> _post(String path, [Map<String, dynamic>? body]) async {
    final resp = await http.post(Uri.parse('$apiBaseUrl$path'), headers: _headers, body: body == null ? null : jsonEncode(body));
    return _handle(resp);
  }

  Future<dynamic> _patch(String path, Map<String, dynamic> body) async {
    final resp = await http.patch(Uri.parse('$apiBaseUrl$path'), headers: _headers, body: jsonEncode(body));
    return _handle(resp);
  }

  Future<dynamic> _delete(String path) async {
    final resp = await http.delete(Uri.parse('$apiBaseUrl$path'), headers: _headers);
    return _handle(resp);
  }

  dynamic _handle(http.Response resp) {
    if (resp.statusCode == 204 || resp.body.isEmpty) return null;
    dynamic decoded;
    try {
      decoded = jsonDecode(resp.body);
    } on FormatException {
      // Not JSON at all — a proxy/tunnel error page (Cloudflare's HTML "502"/"1033" pages, for
      // instance) rather than a real response from the API. Surface something a member can act
      // on instead of a raw parser stack trace.
      throw ApiException('Could not reach the server — check your connection and try again.', resp.statusCode);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(decoded is Map ? (decoded['error'] ?? 'Request failed') : 'Request failed (${resp.statusCode})', resp.statusCode);
    }
    return decoded;
  }

  // --- Auth ---
  Future<Session> login(String email, String password) async {
    final j = await _post('/login', {'email': email, 'password': password});
    return Session.fromJson(j);
  }

  Future<Session> me() async => Session.fromJson(await _get('/me'));

  // --- Family / members ---
  Future<Map<String, dynamic>> getFamily({bool includeArchived = false}) async => await _get('/family${includeArchived ? '?include_archived=1' : ''}');
  Future<void> addMember(Map<String, dynamic> payload) => _post('/family/members', payload);
  Future<void> archiveMember(String memberId) => _post('/members/$memberId/archive', {});
  Future<void> restoreMember(String memberId) => _post('/members/$memberId/restore', {});
  Future<Map<String, dynamic>> getSummary(String memberId) async => await _get('/members/$memberId/summary');
  Future<void> addAllergy(String memberId, String value) => _post('/members/$memberId/allergies', {'value': value});
  Future<void> addChronicCondition(String memberId, String value) => _post('/members/$memberId/chronic-conditions', {'value': value});
  Future<void> updateMemberProfile(String memberId, Map<String, dynamic> payload) => _patch('/members/$memberId/profile', payload);
  Future<List<dynamic>> getCareReminders() async => (await _get('/family/care-reminders') as Map<String, dynamic>)['reminders'] as List<dynamic>;

  // --- Insurance ---
  Future<List<dynamic>> getInsurance(String memberId) async => await _get('/members/$memberId/insurance');
  Future<void> addInsurance(String memberId, Map<String, dynamic> payload) => _post('/members/$memberId/insurance', payload);
  Future<void> deleteInsurance(String id) => _delete('/insurance/$id');

  // --- Health / extraction mode ---
  Future<String> getExtractionMode() async {
    final j = await _get('/health') as Map<String, dynamic>;
    return j['extractionMode'] as String? ?? 'mock';
  }

  // --- Documents ---
  Future<List<dynamic>> getDocuments(String memberId) async => await _get('/documents?member_id=$memberId');
  Future<Map<String, dynamic>> getDocument(String id) async => await _get('/documents/$id');
  Future<List<dynamic>> getDocumentPages(String id) async => await _get('/documents/$id/pages');

  /// The original uploaded file's bytes, for viewing the source document (not just its parsed
  /// values). Needs the auth header, so a plain Image.network URL won't work — fetched manually.
  Future<Uint8List> getDocumentFileBytes(String documentId, String filename) async {
    final resp = await http.get(Uri.parse('$apiBaseUrl/documents/$documentId/file/$filename'), headers: _headers);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException('Could not load the original file (${resp.statusCode})', resp.statusCode);
    }
    return resp.bodyBytes;
  }

  Future<Map<String, dynamic>> uploadDocument({
    required String memberId,
    required String documentType,
    String? mockFixture,
    List<PickedFileBytes> files = const [],
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/documents'));
    if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
    req.fields['member_id'] = memberId;
    req.fields['document_type'] = documentType;
    if (mockFixture != null) req.fields['mock_fixture'] = mockFixture;

    if (mockFixture != null && files.isEmpty) {
      req.files.add(http.MultipartFile.fromBytes('pages', utf8.encode('sample'), filename: 'sample.png', contentType: MediaType('image', 'png')));
    }
    for (final f in files) {
      req.files.add(http.MultipartFile.fromBytes('pages', f.bytes, filename: f.filename, contentType: _mediaTypeForFilename(f.filename)));
    }
    // Positional (matches `files` order), not filename-keyed — filenames can collide (e.g. the
    // same source PDF picked more than once), so index is the only unambiguous way to line a
    // page selection up with the right multipart file server-side.
    if (files.any((f) => f.selectedPages != null)) {
      req.fields['page_selections'] = jsonEncode(files.map((f) => f.selectedPages).toList());
    }

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    return _handle(resp) as Map<String, dynamic>;
  }

  // --- Parameters / trends / review ---
  Future<Map<String, dynamic>> getTrends(String memberId) async => await _get('/parameters/trends?member_id=$memberId');
  Future<Map<String, dynamic>> getHealthInsights(String memberId) async => await _get('/parameters/health-insights?member_id=$memberId');
  Future<List<dynamic>> getVitals(String memberId) async => await _get('/parameters/vitals?member_id=$memberId');

  // --- Manual Vitals entry (heart rate/BP/respiratory rate/SpO2/temp/weight/height/head
  // circumference), separate from the document-derived /parameters/vitals above. ---
  Future<Map<String, dynamic>> getVitalsEntries(String memberId) async => await _get('/members/$memberId/vitals-entries');
  Future<void> addVitalsEntry(String memberId, Map<String, dynamic> payload) => _post('/members/$memberId/vitals-entries', payload);

  Future<List<dynamic>> getHealthTimeline(String memberId) async =>
      (await _get('/parameters/health-timeline?member_id=$memberId') as Map<String, dynamic>)['timeline'] as List<dynamic>;
  Future<List<dynamic>> getHealthAnalysisCategories() async => await _get('/parameters/health-analysis/categories');
  Future<Map<String, dynamic>> getHealthAnalysis(String memberId, String category) async =>
      await _get('/parameters/health-analysis?member_id=$memberId&category=${Uri.encodeComponent(category)}');
  Future<List<dynamic>> getReviewQueue(String memberId) async => await _get('/parameters/review-queue?member_id=$memberId');
  Future<void> confirmParameter(String id) => _post('/parameters/$id/confirm');
  Future<void> correctParameter(String id, Map<String, dynamic> payload) => _post('/parameters/$id/correct', payload);
  Future<void> rejectParameter(String id) => _post('/parameters/$id/reject');

  // --- Prescriptions / audit ---
  Future<List<dynamic>> getPrescriptions(String memberId) async => await _get('/prescriptions?member_id=$memberId');
  Future<List<dynamic>> getAudit(String memberId) async => await _get('/audit?member_id=$memberId');

  // --- Medications ---
  Future<List<dynamic>> getMedications(String memberId) async => await _get('/members/$memberId/medications');
  Future<Map<String, dynamic>> getMedicationsToday(String memberId) async => await _get('/members/$memberId/medications/today');
  Future<Map<String, dynamic>> getMedication(String id) async => await _get('/medications/$id');
  Future<Map<String, dynamic>> addMedication(String memberId, Map<String, dynamic> payload) async => await _post('/members/$memberId/medications', payload);
  Future<void> updateMedication(String id, Map<String, dynamic> payload) => _patch('/medications/$id', payload);
  Future<void> deleteMedication(String id) => _delete('/medications/$id');
  Future<void> logMedicationDose(String scheduleId, Map<String, dynamic> payload) => _post('/medications/$scheduleId/doses', payload);

  // --- Lab Tests ---
  Future<List<dynamic>> getLabTestCatalog() async => await _get('/lab-tests/catalog');
  Future<List<dynamic>> getFamilyLabTestBookings() async => await _get('/family/lab-test-bookings');
  Future<List<dynamic>> getMemberLabTestBookings(String memberId) async => await _get('/members/$memberId/lab-test-bookings');
  Future<Map<String, dynamic>> addLabTestBooking(Map<String, dynamic> payload) async => await _post('/lab-test-bookings', payload);
  Future<void> updateLabTestBooking(String id, Map<String, dynamic> payload) => _patch('/lab-test-bookings/$id', payload);

  // --- Invoices & payment (demo flow — no real payment gateway; "pay" just marks it paid) ---
  Future<List<dynamic>> getFamilyInvoices() async => await _get('/family/invoices');
  Future<List<dynamic>> getMemberInvoices(String memberId) async => await _get('/members/$memberId/invoices');
  Future<Map<String, dynamic>> getAppointmentInvoice(String appointmentId) async => await _get('/appointments/$appointmentId/invoice');
  Future<void> payInvoice(String invoiceId, String paymentMethod) => _post('/invoices/$invoiceId/pay', {'payment_method': paymentMethod});

  // --- Pharmacy orders (medicine ordering — demo delivery timeline, no real courier) ---
  Future<List<dynamic>> getPharmacyOrders(String memberId) async => await _get('/members/$memberId/pharmacy-orders');
  Future<Map<String, dynamic>> placePharmacyOrder(String memberId, Map<String, dynamic> payload) async => await _post('/members/$memberId/pharmacy-orders', payload);
  Future<void> updatePharmacyOrder(String id, String status) => _patch('/pharmacy-orders/$id', {'status': status});

  // --- Translation (Symptoms' voice-in-your-language logging) ---
  Future<String> translateText(String text, String sourceLanguage) async =>
      (await _post('/translate', {'text': text, 'source_language': sourceLanguage}) as Map<String, dynamic>)['translated'] as String;

  // --- Appointments ---
  Future<List<dynamic>> getProviders() async => await _get('/providers');
  Future<List<dynamic>> getNearbyProviders({required String specialty, required double lat, required double lng, double radiusKm = 20}) async =>
      await _get('/providers/nearby?specialty=${Uri.encodeComponent(specialty)}&lat=$lat&lng=$lng&radius_km=$radiusKm');
  Future<List<dynamic>> getPreferredProviders(String memberId) async => await _get('/members/$memberId/preferred-providers');
  Future<void> addPreferredProvider(String memberId, String providerId) => _post('/members/$memberId/preferred-providers', {'provider_id': providerId});
  Future<void> removePreferredProvider(String memberId, String providerId) => _delete('/members/$memberId/preferred-providers/$providerId');
  Future<List<dynamic>> searchProviders(String query) async => await _get('/providers/search?q=${Uri.encodeComponent(query)}');
  Future<List<dynamic>> getAppointments() async => await _get('/appointments');
  Future<Map<String, dynamic>> getAppointment(String id) async => await _get('/appointments/$id');
  Future<void> bookAppointment(Map<String, dynamic> payload) => _post('/appointments', payload);
  Future<void> editAppointment(String id, Map<String, dynamic> payload) => _patch('/appointments/$id', payload);
  Future<void> cancelAppointment(String id) => _post('/appointments/$id/cancel', {});
  Future<void> checkIn(String id) => _post('/appointments/$id/check-in', {});
  Future<Map<String, dynamic>> requestConsent(String id, String method) async =>
      await _post('/appointments/$id/request-consent', {'method': method});
  Future<Map<String, dynamic>> resendConsent(String id, String method) async =>
      await _post('/appointments/$id/resend-consent', {'method': method});
  Future<void> respondConsent(String id, bool approve) => _post('/appointments/$id/respond-consent', {'approve': approve});
  Future<Map<String, dynamic>> getConsentExplanation(String appointmentId) async => await _get('/appointments/$appointmentId/consent-explanation');
  Future<Map<String, dynamic>> getPrevisitBrief(String appointmentId) async => await _get('/appointments/$appointmentId/previsit-brief');
  Future<List<dynamic>> reconcileDraft(String appointmentId, List<Map<String, dynamic>> lineItems) async =>
      (await _post('/appointments/$appointmentId/reconcile-draft', {'line_items': lineItems}) as Map<String, dynamic>)['flags'] as List<dynamic>;
  Future<void> verifyOtp(String id, String otp) => _post('/appointments/$id/verify-otp', {'otp': otp});
  Future<void> startConsultation(String id) => _post('/appointments/$id/start-consultation', {});
  Future<void> issuePrescription(String id, Map<String, dynamic> payload) => _post('/appointments/$id/prescriptions', payload);
  Future<void> completeVisit(String id) => _post('/appointments/$id/complete', {});

  // --- AI health chat ---
  Future<List<dynamic>> getChatHistory(String memberId) async => await _get('/members/$memberId/chat');

  // --- Symptom intake agent ---
  Future<List<dynamic>> getSymptomEntries(String memberId) async => await _get('/members/$memberId/symptom-entries');
  Future<List<dynamic>> getConsultationSymptomHistory(String memberId) async => await _get('/members/$memberId/consultation-symptom-history');
  Future<List<dynamic>> getFamilyMedicationsToday() async => await _get('/family/medications-today');

  // --- Cross-provider safety net ---
  Future<Map<String, dynamic>> getSafetyFlags(String memberId) async => await _get('/members/$memberId/safety-flags');
  Future<void> dismissSafetyFlag(String id) => _post('/safety-flags/$id/dismiss');
  Future<void> markSafetyFlagDiscussed(String id) => _post('/safety-flags/$id/discussed');
  Future<List<dynamic>> getFamilySafetyFlagsSummary() async => await _get('/family/safety-flags-summary');
  Future<Map<String, dynamic>> getSymptomEntry(String entryId) async => await _get('/symptom-entries/$entryId');
  Future<Map<String, dynamic>> startSymptomEntry(String memberId, String message) async =>
      await _post('/members/$memberId/symptom-entries', {'message': message});
  Future<Map<String, dynamic>> continueSymptomEntry(String entryId, String message) async =>
      await _post('/symptom-entries/$entryId/messages', {'message': message});
  Future<Map<String, dynamic>> sendChatMessage(String memberId, String message) async =>
      await _post('/members/$memberId/chat', {'message': message}) as Map<String, dynamic>;
  Future<void> clearChatHistory(String memberId) => _delete('/members/$memberId/chat');

  // --- Admin ---
  Future<List<dynamic>> getCandidates({String status = 'pending'}) async => await _get('/admin/candidates?status=$status');
  Future<void> resolveCandidate(String id, Map<String, dynamic> payload) => _post('/admin/candidates/$id/resolve', payload);

  // --- Dictionary curation agent ---
  Future<Map<String, dynamic>> getCandidateDraft(String id) async => await _get('/admin/candidates/$id/draft');
  Future<List<dynamic>> getDriftFlags({String status = 'open'}) async => await _get('/admin/dictionary/drift-flags?status=$status');
  Future<List<dynamic>> scanDictionaryDrift({String? canonicalParameterId}) async =>
      (await _post('/admin/dictionary/drift-scan', canonicalParameterId != null ? {'canonical_parameter_id': canonicalParameterId} : {}) as Map<String, dynamic>)['newly_flagged'] as List<dynamic>;
  Future<void> dismissDriftFlag(String id) => _post('/admin/dictionary/drift-flags/$id/dismiss', {});
}

class PickedFileBytes {
  final String filename;
  final List<int> bytes;
  /// 1-indexed page numbers to extract from this PDF before sending it for extraction — null
  /// (or omitted) means "use the whole file" (the default for images, and for PDFs the user
  /// didn't trim down via the page picker).
  final List<int>? selectedPages;
  PickedFileBytes(this.filename, this.bytes, {this.selectedPages});
}
