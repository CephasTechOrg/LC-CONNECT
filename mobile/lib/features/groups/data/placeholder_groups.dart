/// Placeholder campus groups — UI only until Groups API exists.
library;

import 'package:flutter/material.dart';

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

  String get membersLabel => '$members members';

  IconData get iconData => switch (icon) {
        IconKind.heart => Icons.favorite_border_rounded,
        IconKind.code => Icons.code_rounded,
        IconKind.link => Icons.link_rounded,
        IconKind.users => Icons.groups_outlined,
      };
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
