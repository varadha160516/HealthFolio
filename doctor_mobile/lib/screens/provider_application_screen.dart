import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../api_client.dart';
import '../auth_provider.dart';
import '../theme.dart';
import 'application_submitted_screen.dart';

const _kDocLabels = {
  'registration_certificate': 'Medical registration certificate',
  'government_id': 'Government-issued ID',
  'qualification_certificate': 'Qualification certificate (optional)',
};

/// Self-serve provider onboarding — collects everything a platform_admin needs to review and
/// approve a new doctor or clinic front-desk account (see admin_applications_screen.dart for the
/// review side). Nothing submitted here is login-capable until an admin approves it.
class ProviderApplicationScreen extends StatefulWidget {
  /// When resubmitting a previously rejected application, pass its full detail back in — the form
  /// prefills from it and posts to the resubmit endpoint instead of creating a new application.
  final Map<String, dynamic>? existingApplication;
  final String? referenceCode;
  const ProviderApplicationScreen({super.key, this.existingApplication, this.referenceCode});

  @override
  State<ProviderApplicationScreen> createState() => _ProviderApplicationScreenState();
}

class _ProviderApplicationScreenState extends State<ProviderApplicationScreen> {
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _phone = TextEditingController();
  final _registrationNumber = TextEditingController();
  final _qualifications = TextEditingController();
  final _yearsOfExperience = TextEditingController();
  final _defaultFee = TextEditingController();
  final _gstNumber = TextEditingController();
  final _newClinicName = TextEditingController();
  final _newClinicAddress = TextEditingController();
  final _newClinicCity = TextEditingController();

  String _role = 'doctor';
  String _clinicMode = 'existing';
  String? _specialty;
  String? _selectedClinicId;
  List<dynamic> _clinics = [];
  List<dynamic> _specializations = [];
  final Map<String, ApplicationFile?> _documents = {'registration_certificate': null, 'government_id': null, 'qualification_certificate': null};
  bool _loadingRefData = true;
  bool _submitting = false;
  String? _error;

  bool get _isResubmit => widget.existingApplication != null;

  @override
  void initState() {
    super.initState();
    _loadRefData();
    final app = widget.existingApplication;
    if (app != null) {
      _fullName.text = app['full_name'] ?? '';
      _email.text = app['email'] ?? '';
      _phone.text = app['phone'] ?? '';
      _role = app['role_requested'] ?? 'doctor';
      _specialty = app['specialty'];
      _registrationNumber.text = app['registration_number'] ?? '';
      _qualifications.text = app['qualifications'] ?? '';
      _yearsOfExperience.text = app['years_of_experience']?.toString() ?? '';
      _defaultFee.text = app['default_fee']?.toString() ?? '';
      _gstNumber.text = app['gst_number'] ?? '';
      _clinicMode = app['clinic_mode'] ?? 'existing';
      _selectedClinicId = app['clinic_id'];
      _newClinicName.text = app['new_clinic_name'] ?? '';
      _newClinicAddress.text = app['new_clinic_address'] ?? '';
      _newClinicCity.text = app['new_clinic_city'] ?? '';
    }
  }

  Future<void> _loadRefData() async {
    final api = context.read<AuthProvider>().api;
    try {
      final results = await Future.wait([api.getPublicSpecializations(), api.getPublicClinics()]);
      if (mounted) {
        setState(() {
          _specializations = results[0];
          _clinics = results[1];
          _loadingRefData = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRefData = false);
    }
  }

  Future<void> _pickDocument(String docType) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Take photo'), onTap: () => Navigator.of(context).pop('camera')),
          ListTile(leading: const Icon(Icons.image_rounded), title: const Text('Choose from gallery'), onTap: () => Navigator.of(context).pop('gallery')),
          ListTile(leading: const Icon(Icons.picture_as_pdf_rounded), title: const Text('Choose PDF'), onTap: () => Navigator.of(context).pop('pdf')),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      if (choice == 'camera' || choice == 'gallery') {
        final picked = await ImagePicker().pickImage(source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery);
        if (picked == null) return;
        final bytes = await picked.readAsBytes();
        setState(() => _documents[docType] = ApplicationFile(documentType: docType, filename: picked.name, bytes: bytes));
      } else {
        final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
        if (picked.isEmpty) return;
        final file = picked.first;
        final bytes = await file.readAsBytes();
        setState(() => _documents[docType] = ApplicationFile(documentType: docType, filename: file.name, bytes: bytes));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not attach file: $e')));
    }
  }

  String? _validate() {
    if (_fullName.text.trim().isEmpty) return 'Full name is required';
    if (_email.text.trim().isEmpty || !_email.text.contains('@')) return 'A valid email is required';
    if (!_isResubmit) {
      if (_password.text.length < 8) return 'Password must be at least 8 characters';
      if (_password.text != _confirmPassword.text) return 'Passwords do not match';
    }
    if (_role == 'doctor' && (_specialty == null || _specialty!.isEmpty)) return 'Please select a specialty';
    if (_clinicMode == 'existing' && _selectedClinicId == null) return 'Please select a clinic';
    if (_clinicMode == 'new' && _newClinicName.text.trim().isEmpty) return 'Clinic name is required';
    if (_documents['registration_certificate'] == null) return 'Please attach your medical registration certificate';
    if (_documents['government_id'] == null) return 'Please attach a government-issued ID';
    return null;
  }

  Future<void> _submit() async {
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final api = context.read<AuthProvider>().api;
    final fields = {
      'email': _email.text.trim(),
      'full_name': _fullName.text.trim(),
      'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      'role_requested': _role,
      'specialty': _role == 'doctor' ? _specialty : null,
      'registration_number': _registrationNumber.text.trim().isEmpty ? null : _registrationNumber.text.trim(),
      'qualifications': _qualifications.text.trim().isEmpty ? null : _qualifications.text.trim(),
      'years_of_experience': _yearsOfExperience.text.trim().isEmpty ? null : _yearsOfExperience.text.trim(),
      'gst_number': _gstNumber.text.trim().isEmpty ? null : _gstNumber.text.trim(),
      'default_fee': _defaultFee.text.trim().isEmpty ? null : _defaultFee.text.trim(),
      'clinic_mode': _clinicMode,
      'clinic_id': _clinicMode == 'existing' ? _selectedClinicId : null,
      'new_clinic_name': _clinicMode == 'new' ? _newClinicName.text.trim() : null,
      'new_clinic_address': _clinicMode == 'new' ? _newClinicAddress.text.trim() : null,
      'new_clinic_city': _clinicMode == 'new' ? _newClinicCity.text.trim() : null,
      if (!_isResubmit) 'password': _password.text,
      if (_isResubmit) 'reference_code': widget.referenceCode,
    };
    final files = _documents.values.whereType<ApplicationFile>().toList();
    try {
      if (_isResubmit) {
        await api.resubmitProviderApplication(widget.existingApplication!['id'] as String, fields, files);
        if (mounted) Navigator.of(context).pop(true);
      } else {
        final result = await api.submitProviderApplication(fields, files);
        if (mounted) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ApplicationSubmittedScreen(referenceCode: result['referenceCode'] as String, email: _email.text.trim())));
        }
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DocGradientScaffold(
      appBar: AppBar(title: Text(_isResubmit ? 'Resubmit application' : 'Apply to join ClinDesk')),
      body: _loadingRefData
          ? const LoadingCenter()
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
              children: [
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: docDangerBg, borderRadius: BorderRadius.circular(docRadiusSm)),
                    child: Text(_error!, style: const TextStyle(color: docDanger, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 14),
                ],
                _sectionLabel('YOUR DETAILS'),
                TextField(controller: _fullName, decoration: const InputDecoration(labelText: 'Full name')),
                const SizedBox(height: 10),
                TextField(controller: _email, enabled: !_isResubmit, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
                if (!_isResubmit) ...[
                  const SizedBox(height: 10),
                  TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password (min. 8 characters)')),
                  const SizedBox(height: 10),
                  TextField(controller: _confirmPassword, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm password')),
                ],
                const SizedBox(height: 10),
                TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (optional)')),
                const SizedBox(height: 18),
                _sectionLabel('ROLE'),
                Row(children: [
                  Expanded(child: _roleTile('doctor', 'Doctor')),
                  const SizedBox(width: 10),
                  Expanded(child: _roleTile('clinic_admin', 'Clinic front desk')),
                ]),
                const SizedBox(height: 18),
                if (_role == 'doctor') ...[
                  _sectionLabel('CREDENTIALS'),
                  DropdownButtonFormField<String>(
                    initialValue: _specialty,
                    decoration: const InputDecoration(labelText: 'Specialty'),
                    items: [for (final s in _specializations) DropdownMenuItem(value: s as String, child: Text(s))],
                    onChanged: (v) => setState(() => _specialty = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: _registrationNumber, decoration: const InputDecoration(labelText: 'Medical registration number')),
                  const SizedBox(height: 10),
                  TextField(controller: _qualifications, decoration: const InputDecoration(labelText: 'Qualifications (e.g. MBBS, MD)')),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(controller: _yearsOfExperience, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Years of experience'))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: _defaultFee, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Consultation fee (₹)'))),
                  ]),
                  const SizedBox(height: 10),
                  TextField(controller: _gstNumber, decoration: const InputDecoration(labelText: 'GST number (optional)')),
                  const SizedBox(height: 18),
                ],
                _sectionLabel('CLINIC'),
                Row(children: [
                  Expanded(child: _clinicModeTile('existing', 'Join existing clinic')),
                  const SizedBox(width: 10),
                  Expanded(child: _clinicModeTile('new', 'Register new clinic')),
                ]),
                const SizedBox(height: 10),
                if (_clinicMode == 'existing')
                  DropdownButtonFormField<String>(
                    initialValue: _selectedClinicId,
                    decoration: const InputDecoration(labelText: 'Clinic'),
                    items: [for (final c in _clinics) DropdownMenuItem(value: c['id'] as String, child: Text('${c['name']}${c['city'] != null ? ' · ${c['city']}' : ''}'))],
                    onChanged: (v) => setState(() => _selectedClinicId = v),
                  )
                else ...[
                  TextField(controller: _newClinicName, decoration: const InputDecoration(labelText: 'Clinic name')),
                  const SizedBox(height: 10),
                  TextField(controller: _newClinicAddress, decoration: const InputDecoration(labelText: 'Address (optional)')),
                  const SizedBox(height: 10),
                  TextField(controller: _newClinicCity, decoration: const InputDecoration(labelText: 'City (optional)')),
                ],
                const SizedBox(height: 18),
                _sectionLabel('VERIFICATION DOCUMENTS'),
                const Text('Reviewed by our team before your account is activated.', style: TextStyle(fontSize: 11.5, color: docMuted)),
                const SizedBox(height: 10),
                for (final docType in _kDocLabels.keys) _documentRow(docType),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : Text(_isResubmit ? 'Resubmit application' : 'Submit application'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 10.5, color: docMutedDim, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
      );

  Widget _roleTile(String value, String label) {
    final selected = _role == value;
    return InkWell(
      borderRadius: BorderRadius.circular(docRadiusMd),
      onTap: () => setState(() => _role = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: selected ? docPrimary : docSurfaceRaised, borderRadius: BorderRadius.circular(docRadiusMd)),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : docTextPrimary, fontWeight: FontWeight.w600, fontSize: 12.5)),
      ),
    );
  }

  Widget _clinicModeTile(String value, String label) {
    final selected = _clinicMode == value;
    return InkWell(
      borderRadius: BorderRadius.circular(docRadiusMd),
      onTap: () => setState(() => _clinicMode = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: selected ? docPrimary : docSurfaceRaised, borderRadius: BorderRadius.circular(docRadiusMd)),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: selected ? Colors.white : docTextPrimary, fontWeight: FontWeight.w600, fontSize: 12)),
      ),
    );
  }

  Widget _documentRow(String docType) {
    final file = _documents[docType];
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(docRadiusMd),
        onTap: () => _pickDocument(docType),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: docSurface, borderRadius: BorderRadius.circular(docRadiusMd), border: docCardBorder, boxShadow: docCardShadow),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: file != null ? docSuccessBg : docAccentLight, borderRadius: BorderRadius.circular(11)),
              child: Icon(file != null ? Icons.check_rounded : Icons.upload_file_rounded, size: 16, color: file != null ? docSuccess : docAccentDark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_kDocLabels[docType]!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                Text(file?.filename ?? 'Tap to attach', style: TextStyle(color: file != null ? docSuccess : docMuted, fontSize: 10.5)),
              ]),
            ),
            if (file != null) IconButton(icon: const Icon(Icons.close_rounded, size: 17), onPressed: () => setState(() => _documents[docType] = null)),
          ]),
        ),
      ),
    );
  }
}
