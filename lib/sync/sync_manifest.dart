import 'dart:convert';

int _asInt(dynamic value) => value is int ? value : (value as num).toInt();

String contentFileOf(String noteId) => 'notes/$noteId.md';

String assetFileOf(String sha) => 'assets/$sha';

class RemoteNotebook {
  RemoteNotebook({
    required this.id,
    required this.name,
    required this.color,
    this.sortKey,
    required this.createAt,
    required this.updateAt,
    required this.deviceId,
    required this.deviceName,
  });

  factory RemoteNotebook.fromJson(Map<String, dynamic> json) => RemoteNotebook(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        color: _asInt(json['color'] ?? 0),
        sortKey: json['sortKey'] == null ? null : _asInt(json['sortKey']),
        createAt: _asInt(json['createAt'] ?? 0),
        updateAt: _asInt(json['updateAt'] ?? 0),
        deviceId: json['deviceId'] as String? ?? '',
        deviceName: json['deviceName'] as String? ?? '',
      );

  final String id;
  final String name;
  final int color;
  final int? sortKey;
  final int createAt;
  final int updateAt;
  final String deviceId;
  final String deviceName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        if (sortKey != null) 'sortKey': sortKey,
        'createAt': createAt,
        'updateAt': updateAt,
        'deviceId': deviceId,
        'deviceName': deviceName,
      };
}

class RemoteNote {
  RemoteNote({
    required this.id,
    required this.notebookId,
    required this.title,
    this.sortKey,
    required this.createAt,
    required this.updateAt,
    this.deletedAt,
    required this.deviceId,
    required this.deviceName,
    List<String>? assets,
  }) : assets = assets ?? const [];

  factory RemoteNote.fromJson(Map<String, dynamic> json) => RemoteNote(
        id: json['id'] as String,
        notebookId: json['notebookId'] as String,
        title: json['title'] as String? ?? '',
        sortKey: json['sortKey'] == null ? null : _asInt(json['sortKey']),
        createAt: _asInt(json['createAt'] ?? 0),
        updateAt: _asInt(json['updateAt'] ?? 0),
        deletedAt:
            json['deletedAt'] == null ? null : _asInt(json['deletedAt']),
        deviceId: json['deviceId'] as String? ?? '',
        deviceName: json['deviceName'] as String? ?? '',
        assets: [
          for (final item in (json['assets'] as List? ?? [])) item as String,
        ],
      );

  final String id;
  final String notebookId;
  final String title;
  final int? sortKey;
  final int createAt;
  final int updateAt;
  final int? deletedAt;
  final String deviceId;
  final String deviceName;
  final List<String> assets;

  Map<String, dynamic> toJson() => {
        'id': id,
        'notebookId': notebookId,
        'title': title,
        if (sortKey != null) 'sortKey': sortKey,
        'createAt': createAt,
        'updateAt': updateAt,
        if (deletedAt != null) 'deletedAt': deletedAt,
        'deviceId': deviceId,
        'deviceName': deviceName,
        if (assets.isNotEmpty) 'assets': assets,
      };
}

class RemoteTombstone {
  RemoteTombstone(
      {required this.id, required this.kind, required this.deletedAt});

  factory RemoteTombstone.fromJson(Map<String, dynamic> json) =>
      RemoteTombstone(
        id: json['id'] as String,
        kind: json['kind'] as String,
        deletedAt: _asInt(json['deletedAt'] ?? 0),
      );

  final String id;
  final String kind;
  final int deletedAt;

  Map<String, dynamic> toJson() =>
      {'id': id, 'kind': kind, 'deletedAt': deletedAt};
}

class SyncManifest {
  SyncManifest({
    this.version = 1,
    this.updatedAt = 0,
    Map<String, RemoteNotebook>? notebooks,
    Map<String, RemoteNote>? notes,
    Set<String>? assets,
    Map<String, String>? assetNames,
    Map<String, RemoteTombstone>? tombstones,
  })  : notebooks = notebooks ?? {},
        notes = notes ?? {},
        assets = assets ?? {},
        assetNames = assetNames ?? {},
        tombstones = tombstones ?? {};

  factory SyncManifest.decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return SyncManifest(
      version: _asInt(json['version'] ?? 1),
      updatedAt: _asInt(json['updatedAt'] ?? 0),
      notebooks: {
        for (final item in (json['notebooks'] as List? ?? []))
          (item as Map<String, dynamic>)['id'] as String:
              RemoteNotebook.fromJson(item),
      },
      notes: {
        for (final item in (json['notes'] as List? ?? []))
          (item as Map<String, dynamic>)['id'] as String:
              RemoteNote.fromJson(item),
      },
      assets: {
        for (final item in (json['assets'] as List? ?? [])) item as String,
      },
      assetNames: {
        for (final entry
            in (json['assetNames'] as Map? ?? {}).entries)
          entry.key as String: entry.value as String,
      },
      tombstones: {
        for (final item in (json['tombstones'] as List? ?? []))
          (item as Map<String, dynamic>)['id'] as String:
              RemoteTombstone.fromJson(item),
      },
    );
  }

  final int version;
  int updatedAt;
  final Map<String, RemoteNotebook> notebooks;
  final Map<String, RemoteNote> notes;
  final Set<String> assets;
  final Map<String, String> assetNames;
  final Map<String, RemoteTombstone> tombstones;

  bool get isEmpty =>
      notebooks.isEmpty &&
      notes.isEmpty &&
      assets.isEmpty &&
      tombstones.isEmpty;

  String encode() {
    final notebookList = notebooks.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final noteList = notes.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final assetList = assets.toList()..sort();
    final tombstoneList = tombstones.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final nameKeys = assetNames.keys.toList()..sort();
    return jsonEncode({
      'version': version,
      'updatedAt': updatedAt,
      'notebooks': [for (final n in notebookList) n.toJson()],
      'notes': [for (final n in noteList) n.toJson()],
      'assets': assetList,
      'assetNames': {for (final k in nameKeys) k: assetNames[k]},
      'tombstones': [for (final t in tombstoneList) t.toJson()],
    });
  }
}