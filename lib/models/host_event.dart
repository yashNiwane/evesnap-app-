class HostEvent {
  HostEvent({
    required this.id,
    required this.hostId,
    required this.name,
    required this.details,
    required this.theme,
    required this.revealTime,
    required this.photoLimit,
    required this.isManuallyRevealed,
    required this.link,
    this.coverPath,
    this.guestCount = 0,
    this.photoCount = 0,
  });

  final String id;
  final String hostId;
  final String name;
  final String details;
  final String theme;
  final DateTime revealTime;
  final int photoLimit;
  bool isManuallyRevealed;
  final String link;
  String? coverPath;
  String? coverSignedUrl;
  int guestCount;
  int photoCount;

  bool get isRevealed =>
      isManuallyRevealed || DateTime.now().isAfter(revealTime);

  factory HostEvent.fromMap(
    Map<String, dynamic> map, {
    required String guestWebBaseUrl,
  }) {
    final id = map['id'] as String;
    final link = Uri.parse(
      guestWebBaseUrl,
    ).replace(queryParameters: {'event_id': id}).toString();
    return HostEvent(
      id: id,
      hostId: map['host_id'] as String,
      name: map['name'] as String,
      details: (map['details'] as String?) ?? '',
      theme: (map['theme'] as String?) ?? 'minimal',
      revealTime: DateTime.parse(map['reveal_time'] as String).toLocal(),
      photoLimit: map['photo_limit'] as int,
      isManuallyRevealed: (map['is_revealed'] as bool?) ?? false,
      coverPath: map['cover_path'] as String?,
      link: link,
    );
  }
}
