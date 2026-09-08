class LinkPreview {
  final String? domain;
  final String? siteName;
  final String? title;
  final String? description;
  final String? imageUrl;
  final DateTime? fetchedAt;
  final String status; // ok | failed

  const LinkPreview({
    this.domain,
    this.siteName,
    this.title,
    this.description,
    this.imageUrl,
    this.fetchedAt,
    required this.status,
  });

  factory LinkPreview.fromJson(Map<String, dynamic> json) => LinkPreview(
        domain: json['domain'] as String?,
        siteName: json['site_name'] as String?,
        title: json['title'] as String?,
        description: json['description'] as String?,
        imageUrl: json['image_url'] as String?,
        fetchedAt: json['fetched_at'] != null ? DateTime.parse(json['fetched_at'] as String) : null,
        status: json['status'] as String? ?? 'failed',
      );

  bool get isOk => status == 'ok';
}

/// Hostname for fallback chips when OG metadata is missing.
String? linkPreviewHost(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host;
  if (host == null || host.isEmpty) return null;
  return host.toLowerCase();
}

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
  final LinkPreview? linkPreview;
  final bool read;
  // Blueprint Bond: 'campus' (staff/admin-authored) or 'employer' (an approved employer
  // partner's opportunity) — drives the source badge. isBlueprintBond drives the opportunities
  // filter — only ever true for a post a verified scholar was already allowed to receive.
  final String source;
  final bool isBlueprintBond;

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
    this.linkPreview,
    this.read = false,
    this.source = 'campus',
    this.isBlueprintBond = false,
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
        linkPreview: json['link_preview'] is Map<String, dynamic>
            ? LinkPreview.fromJson(json['link_preview'] as Map<String, dynamic>)
            : null,
        read: json['read'] as bool? ?? false,
        source: json['source'] as String? ?? 'campus',
        isBlueprintBond: json['is_blueprint_bond'] as bool? ?? false,
      );

  bool get isUrgent => priority == 'urgent';
  bool get isImportant => priority == 'important';
  bool get isEmployerPartner => source == 'employer';

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
        linkPreview: linkPreview,
        read: read ?? this.read,
        source: source,
        isBlueprintBond: isBlueprintBond,
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
    super.linkPreview,
    super.source,
    super.isBlueprintBond,
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
        linkPreview: json['link_preview'] is Map<String, dynamic>
            ? LinkPreview.fromJson(json['link_preview'] as Map<String, dynamic>)
            : null,
        source: json['source'] as String? ?? 'campus',
        isBlueprintBond: json['is_blueprint_bond'] as bool? ?? false,
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
