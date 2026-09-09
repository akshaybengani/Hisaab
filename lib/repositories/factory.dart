import 'contracts.dart';

/// Opens the database and returns the live repository bundle.
///
/// This is the seam between the UI and storage: `main()` calls it, and every
/// screen only ever sees the [Repositories] interface. It exists as its own
/// file so the UI lane can compile and wire providers before the data lane
/// has written a single migration.
///
/// Owned by lane/data.
Future<Repositories> openRepositories() {
  throw UnimplementedError('owned by lane/data');
}
