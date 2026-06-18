/// Optional patient metadata entered by the user (stored locally only; never transmitted except to Gemma API).
class PatientContext {
  final String? patientName;
  final String? dateOfBirth;
  final String? examDate;
  final String? side; // 'Left', 'Right', or 'Bilateral'
  final String? referringClinician;

  const PatientContext({
    this.patientName,
    this.dateOfBirth,
    this.examDate,
    this.side,
    this.referringClinician,
  });

  bool get hasData =>
      patientName != null ||
      dateOfBirth != null ||
      examDate != null ||
      side != null ||
      referringClinician != null;
}
