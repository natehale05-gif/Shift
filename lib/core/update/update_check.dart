import 'dart:convert';

import 'package:http/http.dart' as http;

/// One downloadable file attached to a release.
class ReleaseAsset {
  final String name;
  final String downloadUrl;

  /// Bytes as GitHub recorded them, used to reject a truncated download
  /// before anything is extracted.
  final int size;

  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });
}

/// The newest published release, as the updater needs to see it.
class ReleaseInfo {
  /// The git tag, e.g. `v0.1.1`. Compared against the running version by
  /// `isNewerRelease`.
  final String tag;

  /// The release page, for the "what changed" link and for the platforms
  /// that cannot install without a human.
  final String pageUrl;

  final List<ReleaseAsset> assets;

  const ReleaseInfo({
    required this.tag,
    required this.pageUrl,
    this.assets = const [],
  });
}

/// Reads the newest release off the GitHub API.
///
/// Every failure — offline, rate-limited, 404 before the first release
/// exists, malformed JSON — comes back as `null`. This runs unattended at
/// launch, so it must never throw into the UI, and a check that could not
/// complete must be indistinguishable from "nothing to do".
class UpdateCheck {
  static const repoSlug = 'natehale05-gif/Shift';
  static const releasesPage = 'https://github.com/$repoSlug/releases/latest';

  /// Overridable at build time so the whole updater — check, download, stage,
  /// swap — can be exercised against a local server instead of waiting on a
  /// published release. Compile-time only: a shipped binary cannot be pointed
  /// somewhere else at runtime.
  static const endpointUrl = String.fromEnvironment(
    'SHIFT_UPDATE_API',
    defaultValue: 'https://api.github.com/repos/$repoSlug/releases/latest',
  );

  static final _endpoint = Uri.parse(endpointUrl);

  final http.Client Function() _clientFactory;
  final Duration timeout;

  UpdateCheck({
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 10),
  }) : _clientFactory = clientFactory ?? http.Client.new;

  Future<ReleaseInfo?> fetchLatest() async {
    final client = _clientFactory();
    try {
      final response = await client.get(
        _endpoint,
        headers: const {
          'Accept': 'application/vnd.github+json',
          // GitHub rejects unidentified clients with a 403.
          'User-Agent': 'SHIFT-AI-updater',
        },
      ).timeout(timeout);

      if (response.statusCode != 200) return null;
      return _parse(response.body);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static ReleaseInfo? _parse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;

      final tag = json['tag_name'];
      if (tag is! String || tag.trim().isEmpty) return null;

      final assets = <ReleaseAsset>[];
      final raw = json['assets'];
      if (raw is List) {
        for (final entry in raw) {
          if (entry is! Map) continue;
          final name = entry['name'];
          final url = entry['browser_download_url'];
          final size = entry['size'];
          if (name is String && url is String && size is int && size > 0) {
            assets.add(ReleaseAsset(name: name, downloadUrl: url, size: size));
          }
        }
      }

      final page = json['html_url'];
      return ReleaseInfo(
        tag: tag.trim(),
        pageUrl: page is String && page.isNotEmpty ? page : releasesPage,
        assets: assets,
      );
    } catch (_) {
      return null;
    }
  }
}
