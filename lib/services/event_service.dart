import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/host_event.dart';

class EventService {
  EventService(this._client);

  final SupabaseClient _client;
  static const _lastGuestEventIdKey = 'eve.last_guest_event_id';
  static const _eventColumnsWithCover =
      'id, host_id, name, details, theme, reveal_time, photo_limit, is_revealed, cover_path';
  static const _eventColumnsLegacy =
      'id, host_id, name, details, theme, reveal_time, photo_limit, is_revealed';

  Future<List<HostEvent>> listHostEvents() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    final rows = await _listHostEventRows(user.id);

    final events = (rows as List)
        .map(
          (row) => HostEvent.fromMap(
            Map<String, dynamic>.from(row),
            guestWebBaseUrl: SupabaseConfig.guestWebBaseUrl,
          ),
        )
        .toList();

    for (final event in events) {
      try {
        final stats = await getEventStats(event.id);
        event.guestCount = stats.guestCount;
        event.photoCount = stats.photoCount;
        if (event.coverPath != null && event.coverPath!.isNotEmpty) {
          event.coverSignedUrl = await createCoverSignedUrl(event.coverPath!);
        }
      } catch (_) {
        // A stats policy issue should not hide the host's event list.
      }
    }

    return events;
  }

  Future<HostEvent> getEventById(String eventId) async {
    await ensureGuestSession();
    final row = await _getEventRow(eventId);
    final event = HostEvent.fromMap(
      Map<String, dynamic>.from(row),
      guestWebBaseUrl: SupabaseConfig.guestWebBaseUrl,
    );
    if (event.coverPath != null && event.coverPath!.isNotEmpty) {
      try {
        event.coverSignedUrl = await createCoverSignedUrl(event.coverPath!);
      } catch (_) {
        // The event can still be joined without a cover preview.
      }
    }
    return event;
  }

  Future<void> ensureGuestSession() async {
    if (_client.auth.currentUser != null) return;
    await _client.auth.signInAnonymously();
  }

  Future<dynamic> _getEventRow(String eventId) async {
    try {
      return await _client
          .from('events')
          .select(_eventColumnsWithCover)
          .eq('id', eventId)
          .single();
    } on PostgrestException catch (e) {
      if (e.code != '42703') rethrow;
      return _client
          .from('events')
          .select(_eventColumnsLegacy)
          .eq('id', eventId)
          .single();
    }
  }

  Future<GuestProfile> joinEventAsGuest({
    required String eventId,
    required String nickname,
  }) async {
    await ensureGuestSession();
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Could not create a guest session.');
    }

    final cleanName = nickname.trim();
    final row = await _client
        .from('guests')
        .upsert({
          'event_id': eventId,
          'user_id': user.id,
          'nickname': cleanName,
        }, onConflict: 'event_id,user_id')
        .select('id, event_id, user_id, nickname, joined_at')
        .single();

    final guest = GuestProfile.fromMap(Map<String, dynamic>.from(row));
    await saveLastGuestEventId(eventId);
    return guest;
  }

  Future<void> saveLastGuestEventId(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastGuestEventIdKey, eventId);
  }

  Future<String?> getLastGuestEventId() async {
    final prefs = await SharedPreferences.getInstance();
    final eventId = prefs.getString(_lastGuestEventIdKey);
    if (eventId == null || eventId.trim().isEmpty) return null;
    return eventId;
  }

  Future<void> clearLastGuestEventId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastGuestEventIdKey);
  }

  Future<GuestProfile?> getCurrentGuestProfile(String eventId) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final rows = await _client
        .from('guests')
        .select('id, event_id, user_id, nickname, joined_at')
        .eq('event_id', eventId)
        .eq('user_id', user.id)
        .limit(1);
    if (rows.isEmpty) return null;
    return GuestProfile.fromMap(Map<String, dynamic>.from(rows.first));
  }

  Future<dynamic> _listHostEventRows(String userId) async {
    try {
      return await _client
          .from('events')
          .select(_eventColumnsWithCover)
          .eq('host_id', userId)
          .order('created_at', ascending: false);
    } on PostgrestException catch (e) {
      if (e.code != '42703') rethrow;
      return _client
          .from('events')
          .select(_eventColumnsLegacy)
          .eq('host_id', userId)
          .order('created_at', ascending: false);
    }
  }

  Future<HostEvent> createEvent({
    required String name,
    required String details,
    required String theme,
    required DateTime revealTime,
    required int photoLimit,
    String? coverPath,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('No authenticated host user found.');
    }

    final row = await _createEventRow(
      userId: user.id,
      name: name,
      details: details,
      theme: theme,
      revealTime: revealTime,
      photoLimit: photoLimit,
      coverPath: coverPath,
    );

    return HostEvent.fromMap(
      Map<String, dynamic>.from(row),
      guestWebBaseUrl: SupabaseConfig.guestWebBaseUrl,
    );
  }

  Future<dynamic> _createEventRow({
    required String userId,
    required String name,
    required String details,
    required String theme,
    required DateTime revealTime,
    required int photoLimit,
    String? coverPath,
  }) async {
    final payload = {
      'host_id': userId,
      'name': name,
      'details': details,
      'theme': theme,
      'reveal_time': revealTime.toUtc().toIso8601String(),
      'photo_limit': photoLimit,
      if (coverPath != null) 'cover_path': coverPath,
    };

    try {
      return await _client
          .from('events')
          .insert(payload)
          .select(_eventColumnsWithCover)
          .single();
    } on PostgrestException catch (e) {
      if (_isThemeConstraintError(e)) {
        final withoutTheme = Map<String, dynamic>.from(payload)
          ..remove('theme');
        try {
          return await _client
              .from('events')
              .insert(withoutTheme)
              .select(_eventColumnsWithCover)
              .single();
        } on PostgrestException catch (retryError) {
          if (retryError.code != '42703') rethrow;
          return _client
              .from('events')
              .insert(withoutTheme)
              .select(_eventColumnsLegacy)
              .single();
        }
      }
      if (e.code != '42703') rethrow;
      final legacyPayload = Map<String, dynamic>.from(payload)
        ..remove('cover_path');
      return _client
          .from('events')
          .insert(legacyPayload)
          .select(_eventColumnsLegacy)
          .single();
    }
  }

  bool _isThemeConstraintError(PostgrestException e) {
    if (e.code != '23514') return false;
    final message = e.message.toLowerCase();
    return message.contains('events_theme_check') || message.contains('theme');
  }

  Future<String> uploadEventCover({
    required String eventId,
    required Uint8List bytes,
    required String fileExt,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('No authenticated host user found.');
    }

    final normalizedExt = _normalizeImageExt(fileExt);
    final path =
        '${user.id}/$eventId/${DateTime.now().millisecondsSinceEpoch}.$normalizedExt';

    await _client.storage
        .from(SupabaseConfig.coverBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _contentTypeForImageExt(normalizedExt),
          ),
        );

    return path;
  }

  Future<void> attachEventCover({
    required String eventId,
    required String coverPath,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('No authenticated host user found.');
    }

    await _client
        .from('events')
        .update({'cover_path': coverPath})
        .eq('id', eventId)
        .eq('host_id', user.id);
  }

  Future<String> createCoverSignedUrl(String coverPath) {
    return _client.storage
        .from(SupabaseConfig.coverBucket)
        .createSignedUrl(coverPath, 60 * 60);
  }

  Future<EventPhoto> uploadEventPhoto({
    required String eventId,
    required Uint8List bytes,
    required String fileExt,
    String caption = '',
    String sourceType = 'camera',
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('No authenticated host user found.');
    }

    final normalizedExt = _normalizeImageExt(fileExt);
    final path =
        '$eventId/${user.id}/${DateTime.now().millisecondsSinceEpoch}.$normalizedExt';

    await _client.storage
        .from(SupabaseConfig.photoBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: false,
            contentType: _contentTypeForImageExt(normalizedExt),
          ),
        );

    var nickname = 'Host';
    if (sourceType != 'camera') {
      final guest = await getCurrentGuestProfile(eventId);
      nickname = guest?.nickname ?? 'Guest';
    }

    final payload = {
      'event_id': eventId,
      'user_id': user.id,
      'storage_path': path,
      'caption': caption,
      'source_type': sourceType,
      'nickname_denormalized': nickname,
      'file_size_bytes': bytes.length,
    };
    final capturedIp = await _fetchPublicIpAddress();
    if (capturedIp != null) {
      payload['captured_ip'] = capturedIp;
    }

    final row = await _insertPhotoRow(payload);

    final map = Map<String, dynamic>.from(row);
    final photo = EventPhoto(
      id: _stringValue(map['id'], fallback: path),
      storagePath: _stringValue(map['storage_path'], fallback: path),
      caption: _stringValue(map['caption']),
      sourceType: _stringValue(map['source_type'], fallback: sourceType),
      capturedBy: _displayCaptureName(
        _nullableString(map['nickname_denormalized']),
        sourceType,
      ),
      capturedAt: _parseCreatedAt(map['created_at']),
      capturedIp: _nullableString(map['captured_ip']),
    );
    photo.signedUrl = await _client.storage
        .from(SupabaseConfig.photoBucket)
        .createSignedUrl(photo.storagePath, 60 * 60);
    return photo;
  }

  Future<Uint8List> downloadPhotoBytes(String storagePath) {
    return _client.storage
        .from(SupabaseConfig.photoBucket)
        .download(storagePath);
  }

  Future<void> deleteEventPhoto({
    required String eventId,
    required EventPhoto photo,
  }) async {
    await _client
        .from('photos')
        .delete()
        .eq('id', photo.id)
        .eq('event_id', eventId);

    try {
      await _client.storage.from(SupabaseConfig.photoBucket).remove([
        photo.storagePath,
      ]);
    } catch (_) {
      // The database row is the source of truth for hiding deleted photos.
    }
  }

  Future<void> revealEventNow(String eventId) async {
    await _client
        .from('events')
        .update({'is_revealed': true})
        .eq('id', eventId);
  }

  Future<EventStats> getEventStats(String eventId) async {
    final guests = await _client
        .from('guests')
        .select('id')
        .eq('event_id', eventId);
    final photos = await _client
        .from('photos')
        .select('id')
        .eq('event_id', eventId);
    return EventStats(
      guestCount: (guests as List).length,
      photoCount: (photos as List).length,
    );
  }

  Future<List<EventPhoto>> listEventPhotos(String eventId) async {
    final rows = await _listPhotoRows(eventId);

    final photos = (rows as List)
        .where((row) {
          final map = Map<String, dynamic>.from(row);
          return _nullableString(map['id']) != null &&
              _nullableString(map['storage_path']) != null;
        })
        .map((row) {
          final map = Map<String, dynamic>.from(row);
          return EventPhoto(
            id: _stringValue(map['id']),
            storagePath: _stringValue(map['storage_path']),
            caption: _stringValue(map['caption']),
            sourceType: _stringValue(map['source_type'], fallback: 'gallery'),
            capturedBy: _displayCaptureName(
              _nullableString(map['nickname_denormalized']),
              _nullableString(map['source_type']),
            ),
            capturedAt: _parseCreatedAt(map['created_at']),
            capturedIp: _nullableString(map['captured_ip']),
          );
        })
        .toList();

    for (final photo in photos) {
      photo.signedUrl = await _client.storage
          .from(SupabaseConfig.photoBucket)
          .createSignedUrl(photo.storagePath, 60 * 60);
    }

    return photos;
  }

  Future<dynamic> _insertPhotoRow(Map<String, dynamic> payload) async {
    try {
      return await _client
          .from('photos')
          .insert(payload)
          .select(
            'id, storage_path, caption, source_type, nickname_denormalized, captured_ip, created_at',
          )
          .single();
    } on PostgrestException catch (e) {
      if (!_isMissingCapturedIpColumn(e)) rethrow;
      final legacyPayload = Map<String, dynamic>.from(payload)
        ..remove('captured_ip');
      return _client
          .from('photos')
          .insert(legacyPayload)
          .select(
            'id, storage_path, caption, source_type, nickname_denormalized, created_at',
          )
          .single();
    }
  }

  Future<dynamic> _listPhotoRows(String eventId) async {
    try {
      return await _client
          .from('photos')
          .select(
            'id, storage_path, caption, source_type, nickname_denormalized, captured_ip, created_at',
          )
          .eq('event_id', eventId)
          .order('created_at', ascending: false);
    } on PostgrestException catch (e) {
      if (!_isMissingCapturedIpColumn(e)) rethrow;
      return _client
          .from('photos')
          .select(
            'id, storage_path, caption, source_type, nickname_denormalized, created_at',
          )
          .eq('event_id', eventId)
          .order('created_at', ascending: false);
    }
  }

  bool _isMissingCapturedIpColumn(PostgrestException e) {
    return e.code == '42703' && e.message.contains('captured_ip');
  }

  String _normalizeImageExt(String rawExt) {
    final ext = rawExt.toLowerCase().replaceAll('.', '');
    const allowed = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'};
    if (allowed.contains(ext)) {
      return ext == 'jpeg' ? 'jpg' : ext;
    }
    return 'jpg';
  }

  String _contentTypeForImageExt(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      default:
        return 'image/jpeg';
    }
  }

  String _displayCaptureName(String? rawName, String? sourceType) {
    final name = rawName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return sourceType == 'camera' ? 'Host' : 'Guest';
  }

  DateTime _parseCreatedAt(dynamic value) {
    if (value is String) {
      return DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
    }
    return DateTime.now();
  }

  String _stringValue(dynamic value, {String fallback = ''}) {
    if (value is String && value.trim().isNotEmpty) return value;
    return fallback;
  }

  String? _nullableString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value;
    return null;
  }

  Future<String?> _fetchPublicIpAddress() async {
    try {
      final response = await http
          .get(Uri.https('api.ipify.org', '/', {'format': 'json'}))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;
      return _nullableString(body['ip']);
    } catch (_) {
      return null;
    }
  }
}

class EventStats {
  EventStats({required this.guestCount, required this.photoCount});

  final int guestCount;
  final int photoCount;
}

class GuestProfile {
  GuestProfile({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.nickname,
    required this.joinedAt,
  });

  final String id;
  final String eventId;
  final String userId;
  final String nickname;
  final DateTime joinedAt;

  factory GuestProfile.fromMap(Map<String, dynamic> map) {
    return GuestProfile(
      id: map['id'] as String,
      eventId: map['event_id'] as String,
      userId: map['user_id'] as String,
      nickname: (map['nickname'] as String?) ?? 'Guest',
      joinedAt: DateTime.parse(map['joined_at'] as String).toLocal(),
    );
  }
}

class EventPhoto {
  EventPhoto({
    required this.id,
    required this.storagePath,
    required this.caption,
    required this.sourceType,
    this.capturedBy,
    this.capturedAt,
    this.capturedIp,
  });

  final String id;
  final String storagePath;
  final String caption;
  final String sourceType;
  final String? capturedBy;
  final DateTime? capturedAt;
  final String? capturedIp;
  String? signedUrl;

  String get displayCapturedBy {
    final name = capturedBy?.trim();
    return name == null || name.isEmpty ? 'Guest' : name;
  }

  DateTime get displayCapturedAt => capturedAt ?? DateTime.now();
}
