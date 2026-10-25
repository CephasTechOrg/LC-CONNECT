import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// Typography for the policy documents, on the app's type scale.
///
/// The documents lean on tables (what we store, who sees it, how long we keep it) and blockquotes,
/// so those get real styling rather than the package defaults — the table of what is stored and
/// for how long is the part a reader most needs to scan. It used to be a full grid with centred
/// headers; it is now rows on rules, the header tinted and left-aligned like every other list.
MarkdownStyleSheet policyMarkdownStyle() {
  final body = AppTypography.bodyLarge.copyWith(color: AppColors.textMid, height: 1.6);
  final dark = body.copyWith(color: AppColors.textDark);
  const rule = BorderSide(color: AppColors.border);

  return MarkdownStyleSheet(
    p: body,
    pPadding: const EdgeInsets.only(bottom: AppSpacing.md),
    h1: AppTypography.display.copyWith(color: AppColors.textDark, height: 1.25),
    h1Padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    h2: AppTypography.title.copyWith(color: AppColors.textDark),
    h2Padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.xs),
    h3: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w700, color: AppColors.textDark),
    h3Padding: const EdgeInsets.only(top: AppSpacing.sm),
    h4: dark.copyWith(fontWeight: FontWeight.w700),
    // Inline styles set no size, so they take the size of the text they sit in. With a full body
    // style, bold words in a 13px table cell rendered at 15px — the "Data" column looked like a
    // second set of headings.
    strong: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark),
    em: const TextStyle(fontStyle: FontStyle.italic),
    a: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primaryText),
    listBullet: body,
    blockSpacing: AppSpacing.md,
    code: GoogleFonts.robotoMono(
      fontSize: 13,
      color: AppColors.textDark,
      backgroundColor: AppColors.background,
    ),
    codeblockDecoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: AppRadii.all(AppRadii.lg),
    ),
    blockquote: dark,
    blockquotePadding: const EdgeInsets.all(AppSpacing.md),
    blockquoteDecoration: BoxDecoration(
      color: AppColors.primarySoft,
      borderRadius: AppRadii.all(AppRadii.lg),
      border: const Border(left: BorderSide(color: AppColors.primary, width: 3)),
    ),
    horizontalRuleDecoration: const BoxDecoration(border: Border(top: rule)),
    tableHead: AppTypography.bodySmall.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.textDark,
      height: 1.4,
    ),
    tableBody: AppTypography.bodySmall.copyWith(color: AppColors.textMid, height: 1.5),
    tableHeadAlign: TextAlign.left,
    tableHeadCellsDecoration: const BoxDecoration(color: AppColors.primarySoft),
    tableBorder: const TableBorder(top: rule, bottom: rule, horizontalInside: rule),
    tableVerticalAlignment: TableCellVerticalAlignment.top,
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
  );
}
