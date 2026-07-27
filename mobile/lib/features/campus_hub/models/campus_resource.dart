class CampusResource {
  final String id;
  final String category;
  final String title;
  final String description;
  final String? location;
  final String? hours;
  final String? contactEmail;
  final String? phone;
  final String? externalUrl;
  final int sortOrder;

  const CampusResource({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    this.location,
    this.hours,
    this.contactEmail,
    this.phone,
    this.externalUrl,
    required this.sortOrder,
  });

  factory CampusResource.fromJson(Map<String, dynamic> json) => CampusResource(
        id: json['id'] as String,
        category: json['category'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        location: json['location'] as String?,
        hours: json['hours'] as String?,
        contactEmail: json['contact_email'] as String?,
        phone: json['phone'] as String?,
        externalUrl: json['external_url'] as String?,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );
}

const resourceCategories = <String, String>{
  'all': 'All',
  'housing': 'Housing',
  'advising': 'Advising',
  'financial_aid': 'Financial Aid',
  'registrar': 'Registrar',
  'safety': 'Safety',
  'it': 'IT',
  'academic_support': 'Academic Support',
  'other': 'Other',
};
