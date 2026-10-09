class DownloadItem {
  const DownloadItem({
    required this.id,
    required this.name,
    required this.path,
    required this.sourceUrl,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
    required this.location,
  });

  final String id;
  final String name;
  /// A local file path for app storage, or a content URI/public path for Downloads.
  final String path;
  final String sourceUrl;
  final String mimeType;
  final int sizeBytes;
  final DateTime createdAt;
  final String location; // 'app' or 'downloads'

  bool get isPublic => location == 'downloads';

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'path': path,
        'sourceUrl': sourceUrl,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'createdAt': createdAt.toIso8601String(),
        'location': location,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    final location = json['location'] == 'downloads' ? 'downloads' : 'app';
    return DownloadItem(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      sourceUrl: json['sourceUrl'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      location: location,
    );
  }
}
