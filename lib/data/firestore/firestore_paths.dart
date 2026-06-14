import 'package:cloud_firestore/cloud_firestore.dart';

class FirestorePaths {
  FirestorePaths(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> user(String uid) =>
      _db.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> applications(String uid) =>
      user(uid).collection('applications');

  CollectionReference<Map<String, dynamic>> resumes(String uid) =>
      user(uid).collection('resumes');

  CollectionReference<Map<String, dynamic>> pipeline(String uid) =>
      user(uid).collection('pipeline');

  CollectionReference<Map<String, dynamic>> briefs(String uid) =>
      user(uid).collection('briefs');

  CollectionReference<Map<String, dynamic>> conversations(String uid) =>
      user(uid).collection('conversations');

  CollectionReference<Map<String, dynamic>> learnedFacts(String uid) =>
    user(uid).collection('learned_facts');

  CollectionReference<Map<String, dynamic>> jobs() => _db.collection('jobs');

  /// Shared directory of confirmed outreach recipients, keyed by company
  /// domain. See [CompanyContactsRepository] and the `company_contacts` rule.
  CollectionReference<Map<String, dynamic>> companyContacts() =>
      _db.collection('company_contacts');
}
