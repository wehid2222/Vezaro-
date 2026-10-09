import 'package:flutter_test/flutter_test.dart';
import 'package:vezaro/models/download_item.dart';
import 'package:vezaro/services/download_service.dart';

void main() {
  group('DownloadService URL validation', () {
    test('accepts valid HTTP and HTTPS URLs', () {
      expect(DownloadService.parseHttpUrl('https://example.com/file.mp4'), isNotNull);
      expect(DownloadService.parseHttpUrl('http://example.com/file.mp4'), isNotNull);
    });

    test('rejects malformed and unsupported URLs', () {
      expect(DownloadService.parseHttpUrl(''), isNull);
      expect(DownloadService.parseHttpUrl('file:///tmp/file.mp4'), isNull);
      expect(DownloadService.parseHttpUrl('javascript:alert(1)'), isNull);
      expect(DownloadService.parseHttpUrl('https:///missing-host'), isNull);
      expect(DownloadService.parseHttpUrl('https://user:password@example.com/file'), isNull);
    });

    test('detects common platform page URLs without matching lookalike hosts', () {
      expect(DownloadService.isKnownPlatformPage(Uri.parse('https://www.youtube.com/watch?v=abc')), isTrue);
      expect(DownloadService.isKnownPlatformPage(Uri.parse('https://m.tiktok.com/@user/video/1')), isTrue);
      expect(DownloadService.isKnownPlatformPage(Uri.parse('https://youtube.com.attacker.example/file')), isFalse);
      expect(DownloadService.isKnownPlatformPage(Uri.parse('https://example.com/video.mp4')), isFalse);
    });

    test('sanitizes URL file names', () {
      expect(DownloadService.filenameFromUrl(Uri.parse('https://example.com/a%20video.mp4?token=1')), 'a video.mp4');
      expect(DownloadService.filenameFromUrl(Uri.parse('https://example.com/..')), isNot('..'));
    });
  });

  test('DownloadItem serializes and deserializes its metadata', () {
    final original = DownloadItem(
      id: 'test-id',
      name: 'sample.mp4',
      path: '/tmp/sample.mp4',
      sourceUrl: 'https://example.com/sample.mp4',
      mimeType: 'video/mp4',
      sizeBytes: 1234,
      createdAt: DateTime.utc(2026, 10, 9),
      location: 'app',
    );

    final restored = DownloadItem.fromJson(original.toJson());
    expect(restored.id, original.id);
    expect(restored.name, original.name);
    expect(restored.path, original.path);
    expect(restored.sourceUrl, original.sourceUrl);
    expect(restored.mimeType, original.mimeType);
    expect(restored.sizeBytes, original.sizeBytes);
    expect(restored.createdAt, original.createdAt);
    expect(restored.location, original.location);
  });
}
