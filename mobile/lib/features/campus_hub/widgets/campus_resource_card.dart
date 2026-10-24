part of '../screens/campus_resources_screen.dart';

class _ResourceList extends StatelessWidget {
  final List<CampusResource> resources;
  final Future<void> Function(String url) onOpenLink;

  const _ResourceList({required this.resources, required this.onOpenLink});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: resources.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final resource = resources[index];
        return _ResourceCard(
          resource: resource,
          onOpenLink: resource.externalUrl != null ? () => onOpenLink(resource.externalUrl!) : null,
        );
      },
    );
  }
}

/// One office or service, in the same structure as an announcement or opportunity: the category
/// icon on the shared tint, the title leading, a muted line under it, then the details — all
/// starting on one text edge. The category used to be a small blue label *above* the title,
/// which put the least important line first.
class _ResourceCard extends StatelessWidget {
  final CampusResource resource;
  final VoidCallback? onOpenLink;

  const _ResourceCard({required this.resource, this.onOpenLink});

  static const _icon = 48.0;
  static const _gap = AppSpacing.md;

  @override
  Widget build(BuildContext context) {
    final categoryLabel = resourceCategories[resource.category] ?? resource.category;
    final details = [
      (Icons.place_outlined, resource.location),
      (Icons.schedule_rounded, resource.hours),
      (Icons.email_outlined, resource.contactEmail),
      (Icons.phone_outlined, resource.phone),
    ].where((d) => d.$2 != null && d.$2!.trim().isNotEmpty).toList();

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIconTile(
                icon: _resourceIcon(resource.category),
                color: AppColors.primaryText,
                size: _icon,
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resource.title,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      categoryLabel,
                      style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: _icon + _gap, top: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resource.description,
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textMid),
                ),
                if (details.isNotEmpty) const SizedBox(height: AppSpacing.xs),
                for (final (icon, text) in details) _MetaRow(icon: icon, text: text!),
                if (onOpenLink != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  TextButton.icon(
                    onPressed: onOpenLink,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Visit website'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryText,
                      padding: EdgeInsets.zero,
                      textStyle: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTypography.label.copyWith(
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
