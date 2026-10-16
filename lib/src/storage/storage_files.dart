// A bucket's files, as an app sees them (S1).
//
// The server applies the bucket's view rule to every file: a listing holds
// only files the signed-in person may view, and says nothing of the rest.

/// What a listing is ordered by.
enum KoolbaseFileSort {
  /// By path, A to Z (descending: Z to A).
  path,

  /// By when each file was first uploaded.
  createdAt,

  /// By when each file was last replaced.
  updatedAt,

  /// By size.
  size,
}

extension on KoolbaseFileSort {
  String get wire => switch (this) {
        KoolbaseFileSort.path => 'path',
        KoolbaseFileSort.createdAt => 'created_at',
        KoolbaseFileSort.updatedAt => 'updated_at',
        KoolbaseFileSort.size => 'size',
      };
}

/// The query string for a listing.
Map<String, String> koolbaseListQuery({
  required String bucket,
  String? prefix,
  int? limit,
  String? cursor,
  KoolbaseFileSort sort = KoolbaseFileSort.path,
  bool descending = false,
}) =>
    {
      'bucket': bucket,
      if (prefix != null && prefix.isNotEmpty) 'prefix': prefix,
      if (limit != null) 'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      'sort': sort.wire,
      'order': descending ? 'desc' : 'asc',
    };

/// One file.
class KoolbaseFileInfo {
  /// Its path in the bucket: what a record stores to point at it.
  final String path;
  final int size;
  final String? contentType;
  final String? etag;
  final Map<String, String> metadata;
  final String? versionId;

  /// Who uploaded it: a project user's id; null when the project did.
  final String? uploadedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Its permanent link, while its bucket is public; null otherwise -- ask
  /// for a download link instead.
  final String? publicUrl;

  const KoolbaseFileInfo({
    required this.path,
    required this.size,
    this.contentType,
    this.etag,
    this.metadata = const {},
    this.versionId,
    this.uploadedBy,
    required this.createdAt,
    required this.updatedAt,
    this.publicUrl,
  });

  factory KoolbaseFileInfo.fromJson(Map<String, dynamic> json) {
    final raw = json['metadata'] as Map<String, dynamic>?;
    final url = json['public_url'] as String?;
    return KoolbaseFileInfo(
      path: json['path'] as String,
      size: (json['size'] as num?)?.toInt() ?? 0,
      contentType: json['content_type'] as String?,
      etag: json['etag'] as String?,
      metadata: raw == null ? const {} : raw.map((k, v) => MapEntry(k, '$v')),
      versionId: json['version_id'] as String?,
      uploadedBy: json['uploaded_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      publicUrl: (url == null || url.isEmpty) ? null : url,
    );
  }

  /// The file's name: the last part of its path.
  String get name => path.split('/').last;

  /// The file as a map of its fields -- id (its path), path, name, size,
  /// contentType, createdAt, updatedAt, uploadedBy, publicUrl, metadata --
  /// for code that reads fields by name (a Designer screen's rows).
  Map<String, dynamic> toMap() => {
        'id': path,
        'path': path,
        'name': name,
        'size': size,
        'contentType': contentType,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'uploadedBy': uploadedBy,
        'publicUrl': publicUrl,
        'metadata': metadata,
      };
}

/// One page of a listing.
class KoolbaseFilePage {
  final List<KoolbaseFileInfo> files;

  /// Pass to the next call for the page after this one; null at the end.
  /// A page can hold fewer files than asked for -- the server passes over
  /// files you may not view -- and still have a next one.
  final String? nextCursor;

  const KoolbaseFilePage({required this.files, this.nextCursor});

  factory KoolbaseFilePage.fromJson(Map<String, dynamic> json) {
    final cursor = json['next_cursor'] as String?;
    return KoolbaseFilePage(
      files: (json['files'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(KoolbaseFileInfo.fromJson)
          .toList(growable: false),
      nextCursor: (cursor == null || cursor.isEmpty) ? null : cursor,
    );
  }

  bool get hasMore => nextCursor != null;
}
