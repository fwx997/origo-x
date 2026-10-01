import 'dart:convert';
import 'dart:io';
import 'package:xxread/book_sources/models/registered_book_source.dart';
import 'package:xxread/book_sources/xbs/xbs_source.dart';
import 'package:xxread/book_sources/xbs/xbs_discovery.dart';

/// Checks local files without bundling or printing private source rules.
void main(List<String> args) {
  if (args.length != 1) throw ArgumentError('Provide one .xbs or JSON file');
  final parsed = XbsSourceFile.parse(File(args.single).readAsBytesSync());
  final novels = parsed.sources.where((s) => s.type == 'text').toList();
  final ids = <String>{};
  final discoveryFilters = <String, int>{};
  var discoveryActions = 0;
  var filterGroups = 0;
  for (final source in novels) {
    final restored = XbsSource.fromRegistered(
      RegisteredBookSource.fromJson(
        jsonDecode(jsonEncode(source.toRegisteredSource().toJson())),
      ),
    );
    if (jsonEncode(restored.config) != jsonEncode(source.config)) {
      throw StateError('Round-trip changed an original source rule');
    }
    if (!ids.add(restored.id)) throw StateError('Source identity collision');
    final world = stringMap(source.config['bookWorld']);
    discoveryActions += world.length;
    for (final action in world.values) {
      final raw = stringMap(stringMap(action)['moreKeys'])['requestFilters'];
      final kind = raw is List
          ? 'array'
          : raw is Map
          ? 'map'
          : raw is String
          ? 'string'
          : 'none';
      discoveryFilters.update(kind, (count) => count + 1, ifAbsent: () => 1);
      final groups = XbsDiscovery.filterGroups(raw);
      filterGroups += groups.length;
      if ((raw is String && raw.trim().isNotEmpty ||
              raw is List && raw.isNotEmpty) &&
          groups.isEmpty) {
        throw StateError('Original discovery filters were not decoded');
      }
    }
  }
  stdout.writeln(
    jsonEncode({
      'total': parsed.sources.length,
      'novels': novels.length,
      'otherTypes': parsed.sources.length - novels.length,
      'errors': parsed.errors.length,
      'uniqueNovelIds': ids.length,
      'losslessRoundTrip': true,
      'discoveryActions': discoveryActions,
      'discoveryFilterFormats': discoveryFilters,
      'decodedFilterGroups': filterGroups,
    }),
  );
}
