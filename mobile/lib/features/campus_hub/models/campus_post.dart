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
      );

  bool get isUrgent => priority == 'urgent';
  bool get isImportant => priority == 'important';
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
  final List<CampusPostSummary> upcomingDeadlines;

  const CampusHubOverview({
    required this.urgentPosts,
    required this.latestUpdates,
    required this.upcomingDeadlines,
  });

  factory CampusHubOverview.fromJson(Map<String, dynamic> json) => CampusHubOverview(
        urgentPosts: (json['urgent_posts'] as List)
            .map((item) => CampusPostSummary.fromJson(item as Map<String, dynamic>))
            .toList(),
        latestUpdates: (json['latest_updates'] as List)
            .map((item) => CampusPostSummary.fromJson(item as Map<String, dynamic>))
            .toList(),
        upcomingDeadlines: (json['upcoming_deadlines'] as List)
            .map((item) => CampusPostSummary.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

const postKindLabels = <String, String>{
  'update': 'Update',
  'deadline': 'Deadline',
  'opportunity': 'Opportunity',
  'alert': 'Alert',
};
