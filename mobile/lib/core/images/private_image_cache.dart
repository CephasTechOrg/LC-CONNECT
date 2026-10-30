import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Disk cache for images that come from a **private** bucket through short-lived signed URLs —
/// the Blueprint Bond headshot today.
///
/// A signed URL is different on every request, so the default URL-keyed cache can never hit: the
/// headshot used to download again on every visit, save and app resume. Callers therefore pass a
/// stable `cacheKey` that changes only when the image does (the upload time).
///
/// Kept apart from the default cache on purpose: it is small, short-lived, and emptied on sign-out
/// (see `AuthNotifier._clearLocalData`), so a shared device does not keep the previous student's
/// photo.
final privateImageCacheProvider = Provider<BaseCacheManager>(
  (ref) => CacheManager(
    Config(
      'lc_private_images',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 20,
    ),
  ),
);
