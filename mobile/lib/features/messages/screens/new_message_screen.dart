import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../shared/widgets/app_search_field.dart';
import '../../../shared/widgets/app_states.dart';
import '../providers/messages_provider.dart';
import '../providers/staff_messaging_provider.dart';

/// Search students + staff and start a brand-new conversation — no connection required.
/// Only reachable by verified staff (see `canMessageAnyoneProvider`).
class NewMessageScreen extends ConsumerStatefulWidget {
  const NewMessageScreen({super.key});

  @override
  ConsumerState<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends ConsumerState<NewMessageScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  bool _starting = false;
  String? _error;
  List<RecipientSearchResult> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    setState(() => _query = trimmed);
    if (trimmed.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(trimmed));
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await ref.read(staffMessagingServiceProvider).searchRecipients(query);
      if (!mounted || query != _query) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't search right now";
        _loading = false;
      });
    }
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _query = '';
      _results = const [];
    });
  }

  Future<void> _startConversation(RecipientSearchResult recipient) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final thread = await ref.read(staffMessagingServiceProvider).startThread(recipient.userId);
      ref.read(threadsNotifierProvider.notifier).upsertThread(thread);
      if (!mounted) return;
      context.pushReplacement('/messages/${thread.addressingId}', extra: thread);
    } catch (_) {
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Couldn't start that conversation", style: GoogleFonts.dmSans(color: Colors.white)),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.textDark),
                    onPressed: () => context.pop(),
                  ),
                  Text(
                    'New Message',
                    style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textDark),
                  ),
                ],
              ),
            ),
            AppSearchField(
              controller: _searchController,
              hasText: _query.isNotEmpty,
              hint: 'Search by name',
              onChanged: _onSearch,
              onClear: _clearSearch,
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_query.isEmpty) {
      return const AppEmptyState(
        icon: Icons.person_search_rounded,
        title: 'Find someone to message',
        subtitle: 'Search students and staff by name — no connection needed.',
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return AppErrorState(message: _error!, onRetry: () => _search(_query));
    }
    if (_results.isEmpty) {
      return AppEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matches',
        subtitle: 'No one found for "$_query"',
      );
    }
    return AbsorbPointer(
      absorbing: _starting,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _results.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 84, endIndent: 20, color: AppColors.border),
        itemBuilder: (_, i) => _RecipientTile(
          recipient: _results[i],
          onTap: () => _startConversation(_results[i]),
        ),
      ),
    );
  }
}

class _RecipientTile extends StatelessWidget {
  final RecipientSearchResult recipient;
  final VoidCallback onTap;
  const _RecipientTile({required this.recipient, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            AvatarWidget(imageUrl: recipient.avatarUrl, size: 48, cacheScope: recipient.userId),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipient.displayName ?? 'LC Member',
                    style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark),
                  ),
                  if (recipient.subtitle != null)
                    Text(
                      recipient.subtitle!,
                      style: GoogleFonts.dmSans(fontSize: 12.5, color: AppColors.textMuted),
                    )
                  else
                    Text(
                      recipient.role == 'staff' ? 'Staff' : 'Student',
                      style: GoogleFonts.dmSans(fontSize: 12.5, color: AppColors.textMuted),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
