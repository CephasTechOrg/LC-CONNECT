class CampusPostSummary {
  final String id;
  final String kind;
  final String title;
  final String? summary;
  final String priority;
  final String? category;
  final DateTime publishAt;
  final DateTime? expiresAt;
  final String? externalUrl;
  final bool read;

  const CampusPostSummary({
    required this.id,
    required this.kind,
    required this.title,
    this.summary,
    required this.priority,
    this.category,
    required this.publishAt,
    this.expiresAt,
    this.externalUrl,
    this.read = false,
  });

  factory CampusPostSummary.fromJson(Map<String, dynamic> json) => CampusPostSummary(
        id: json['id'] as String,
        kind: json['kind'] as String,
        title: json['title'] as String,
        summary: json['summary'] as String?,
        priority: json['priority'] as String,
        category: json['category'] as String?,
        publishAt: DateTime.parse(json['publish_at'] as String),
        expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at'] as String) : null,
        externalUrl: json['external_url'] as String?,
        read: json['read'] as bool? ?? false,
      );

  bool get isUrgent => priority == 'urgent';
  bool get isImportant => priority == 'important';

  CampusPostSummary copyWith({bool? read}) => CampusPostSummary(
        id: id,
        kind: kind,
        title: title,
        summary: summary,
        priority: priority,
        category: category,
        publishAt: publishAt,
        expiresAt: expiresAt,
        externalUrl: externalUrl,
        read: read ?? this.read,
      );
}

class CampusPost extends CampusPostSummary {
  final String body;
  final String audience;

  const CampusPost({
    required super.id,
    required super.kind,
    required super.title,
    super.summary,
    required super.priority,
    super.category,
    required super.publishAt,
    super.expiresAt,
    super.externalUrl,
    required this.body,
    required this.audience,
  });

  factory CampusPost.fromJson(Map<String, dynamic> json) => CampusPost(
        id: json['id'] as String,
        kind: json['kind'] as String,
        title: json['title'] as String,
        summary: json['summary'] as String?,
        priority: json['priority'] as String,
        category: json['category'] as String?,
        publishAt: DateTime.parse(json['publish_at'] as String),
        expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at'] as String) : null,
        externalUrl: json['external_url'] as String?,
        body: json['body'] as String,
        audience: json['audience'] as String,
      );
}

class CampusHubOverview {
  final List<CampusPostSummary> urgentPosts;
  final List<CampusPostSummary> latestUpdates;

  const CampusHubOverview({
    required this.urgentPosts,
    required this.latestUpdates,
  });

  factory CampusHubOverview.fromJson(Map<String, dynamic> json) => CampusHubOverview(
        urgentPosts: (json['urgent_posts'] as List)
            .map((item) => CampusPostSummary.fromJson(item as Map<String, dynamic>))
            .toList(),
        latestUpdates: (json['latest_updates'] as List)
            .map((item) => CampusPostSummary.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

// Two clear types. Urgency is the post's priority, not a type.
const postKindLabels = <String, String>{
  'announcement': 'Announcement',
  'opportunity': 'Opportunity',
};

// `category` classifies a post within its kind — each kind has its own vocabulary (mirrors the
// backend's `categories_for_kind`), so a publisher only ever sees categories that apply.
const announcementCategoryLabels = <String, String>{
  'general': 'General',
  'academic': 'Academic',
  'campus': 'Campus',
  'events': 'Events',
  'safety': 'Safety',
};

const opportunityCategoryLabels = <String, String>{
  'internship': 'Internships',
  'job': 'Jobs',
  'volunteer': 'Volunteering',
  'leadership': 'Leadership',
};

Map<String, String> categoryLabelsForKind(String kind) =>
    kind == 'opportunity' ? opportunityCategoryLabels : announcementCategoryLabels;
