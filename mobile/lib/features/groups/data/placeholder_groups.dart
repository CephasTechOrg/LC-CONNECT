/// Placeholder campus groups — UI only until Groups API exists.
library;

enum IconKind { heart, code, users, link }

class PlaceholderGroup {
  final String name;
  final String category;
  final int members;
  final String action; // Join | Joined | Request | Pending
  final bool useLc;
  final bool greenTone;
  final IconKind icon;

  const PlaceholderGroup({
    required this.name,
    required this.category,
    required this.members,
    required this.action,
    this.useLc = false,
    this.greenTone = false,
    this.icon = IconKind.users,
  });
}

const groupCategories = [
  'All',
  'Academic',
  'Clubs & Sports',
  'Wellness',
  'Career',
  'Creative',
];

const placeholderGroups = [
  PlaceholderGroup(
    name: 'Livingstone Volleyball',
    category: 'Clubs & Sports',
    members: 124,
    action: 'Joined',
    useLc: true,
  ),
  PlaceholderGroup(
    name: 'Pre-Health Society',
    category: 'Academic',
    members: 98,
    action: 'Join',
    icon: IconKind.heart,
  ),
  PlaceholderGroup(
    name: 'Tech Club',
    category: 'Academic',
    members: 76,
    action: 'Join',
    icon: IconKind.code,
  ),
  PlaceholderGroup(
    name: "Men's Mentorship Circle",
    category: 'Wellness',
    members: 85,
    action: 'Request',
    icon: IconKind.users,
    greenTone: true,
  ),
  PlaceholderGroup(
    name: 'Livingstone Choir',
    category: 'Creative',
    members: 52,
    action: 'Join',
    icon: IconKind.heart,
  ),
  PlaceholderGroup(
    name: 'Career Connect Network',
    category: 'Career',
    members: 64,
    action: 'Join',
    icon: IconKind.link,
  ),
];
