import 'dart:convert';

import 'package:path/path.dart' as p;

/// One entry of a comic-source index document
/// (`{name, key, version, url|fileName}` — same shape as the online
/// `index.json` published in the EZvenera-config repository).
class SourceIndexEntry {
  const SourceIndexEntry({
    required this.name,
    required this.key,
    required this.version,
    this.url,
    this.fileName,
  });

  factory SourceIndexEntry.fromMap(Map<String, dynamic> json) {
    return SourceIndexEntry(
      name: json['name']?.toString() ?? '',
      key: json['key']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      url: json['url']?.toString(),
      fileName: json['fileName']?.toString() ?? json['filename']?.toString(),
    );
  }

  final String name;
  final String key;
  final String version;
  final String? url;
  final String? fileName;

  /// Absolute URL of the source JS, resolved against [indexUrl] unless the
  /// entry carries its own absolute url.
  String resolvedUrl(String indexUrl) {
    if (url != null && url!.isNotEmpty) {
      return url!;
    }
    if (fileName == null || fileName!.isEmpty) {
      throw StateError('Source entry does not contain url or fileName.');
    }

    final uri = Uri.parse(indexUrl);
    final segments = [...uri.pathSegments];
    if (segments.isNotEmpty) {
      segments.removeLast();
    }
    return uri.replace(pathSegments: [...segments, fileName!]).toString();
  }

  /// Local path of the source JS when the index was imported from a local
  /// file; null when the entry has no fileName to resolve. The convention is
  /// that a locally distributed index ships its `.js` files in the same
  /// directory as the index document itself.
  String? resolvedLocalPath(String indexDirectory) {
    final f = fileName;
    if (f == null || f.isEmpty) {
      return null;
    }
    return p.normalize(p.join(indexDirectory, f));
  }
}

/// Parses an index JSON document (a JSON list of source entries).
///
/// Throws [StateError] when [raw] is not valid JSON or not a JSON list.
/// Entries that are not JSON objects, or that carry neither `key` nor `name`,
/// are skipped so one malformed row cannot break the whole index.
List<SourceIndexEntry> parseSourceIndex(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw StateError('Source index is not valid JSON.');
  }
  if (decoded is! List) {
    throw StateError('Source index is not a JSON list.');
  }

  final entries = <SourceIndexEntry>[];
  for (final item in decoded) {
    if (item is! Map) {
      continue;
    }
    final entry = SourceIndexEntry.fromMap(Map<String, dynamic>.from(item));
    if (entry.key.isEmpty && entry.name.isEmpty) {
      continue;
    }
    entries.add(entry);
  }
  return entries;
}
