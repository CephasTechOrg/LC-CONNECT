import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/scholars/providers/scholars_provider.dart';

ScholarProfile _profile({String summary = '', String? version = '2026-10-01T00:00:00Z'}) => ScholarProfile(
      id: 'sp1',
      userId: 'u1',
      summary: summary,
      skills: const [],
      careerInterests: const [],
      employerVisibilityConsent: false,
      hasHeadshot: true,
      headshotVersion: version,
      hasResume: false,
      isComplete: false,
      missingFields: const [],
    );

class _Scholar extends ScholarProfileNotifier {
  int signed = 0;

  @override
  Future<ScholarProfile> build() async => _profile();

  void put(ScholarProfile p) => state = AsyncData(p);

  @override
  Future<String> headshotUrl() async => 'https://signed.example/headshot.jpg?token=${++signed}';
}

void main() {
  late ProviderContainer container;
  late _Scholar scholar;

  setUp(() {
    scholar = _Scholar();
    container = ProviderContainer(overrides: [scholarProfileNotifierProvider.overrideWith(() => scholar)]);
    addTearDown(container.dispose);
    container.listen(scholarHeadshotPreviewProvider, (_, _) {});
  });

  test('the cache key follows the upload, not the signed URL', () async {
    final headshot = await container.read(scholarHeadshotPreviewProvider.future);
    expect(headshot!.cacheKey, 'scholar-headshot:u1:2026-10-01T00:00:00Z');
    expect(headshot.url, contains('token=1'));
  });

  test('saving other fields does not re-sign or re-download the photo', () async {
    await container.read(scholarHeadshotPreviewProvider.future);
    scholar.put(_profile(summary: 'A new summary'));
    await pumpEventQueue();
    await container.read(scholarHeadshotPreviewProvider.future);
    expect(scholar.signed, 1);
  });

  test('a new upload gets a new key', () async {
    await container.read(scholarHeadshotPreviewProvider.future);
    scholar.put(_profile(version: '2026-10-29T09:00:00Z'));
    await pumpEventQueue();
    final headshot = await container.read(scholarHeadshotPreviewProvider.future);
    expect(headshot!.cacheKey, endsWith('2026-10-29T09:00:00Z'));
    expect(scholar.signed, 2);
  });
}
