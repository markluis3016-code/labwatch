import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/data/auth_repository.dart';
import '../domain/activity_entry.dart';
import 'activity_repository.dart';

/// Live activity feed: all entries for admins, own entries for everyone else.
final activityFeedProvider =
    StreamProvider.autoDispose<List<ActivityEntry>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(const <ActivityEntry>[]);

  return ref.watch(activityRepositoryProvider).watch(
        allUsers: user.isAdmin,
        userId: user.uid,
      );
});
