import '../services/database_service.dart';
import 'contracts.dart';
import 'sqflite_repositories.dart';

/// Opens the database and returns the live repository bundle.
///
/// This is the seam between the UI and storage: `main()` calls it, and every
/// screen only ever sees the [Repositories] interface. It exists as its own
/// file so the UI lane can compile and wire providers before the data lane
/// has written a single migration.
///
/// [path] names the database file. Leave it out on a device, where the
/// platform decides where databases live; tests pass a temporary path.
///
/// Owned by lane/data.
Future<Repositories> openRepositories({String? path}) async {
  return SqfliteRepositories(await DatabaseService.open(path: path));
}
