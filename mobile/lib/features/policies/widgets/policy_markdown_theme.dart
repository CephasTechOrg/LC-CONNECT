import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';

/// Typography for the policy documents.
///
/// The documents lean on tables (what we store, who sees it, how long we keep it) and blockquotes,
/// so those get real styling rather than the package defaults — an unstyled table of retention
/// periods is the part a reader most needs to be able to scan.
MarkdownStyleSheet policyMarkdownStyle() {
  TextStyle body(double size, {FontWeight weight = FontWeight.w400, Color? color, double height = 1.6}) =>
      GoogleFonts.dmSans(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.textMid,
        height: height,
      );

  return MarkdownStyleSheet(
    p: body(14.5),
    pPadding: const EdgeInsets.only(bottom: 12),
    h1: body(23, weight: FontWeight.w800, color: AppColors.textDark, height: 1.25),
    h1Padding: const EdgeInsets.only(bottom: 4),
    h2: body(17.5, weight: FontWeight.w700, color: AppColors.textDark, height: 1.3),
    h2Padding: const EdgeInsets.only(top: 20, bottom: 6),
    h3: body(15, weight: FontWeight.w700, color: AppColors.textDark, height: 1.35),
    h4: body(14.5, weight: FontWeight.w700, color: AppColors.textDark),
    strong: body(14.5, weight: FontWeight.w700, color: AppColors.textDark),
    em: GoogleFonts.dmSans(fontSize: 14.5, fontStyle: FontStyle.italic, color: AppColors.textMid, height: 1.6),
    a: body(14.5, weight: FontWeight.w600, color: AppColors.primary),
    listBullet: body(14.5),
    blockSpacing: 10,
    code: GoogleFonts.robotoMono(
      fontSize: 12.5,
      color: AppColors.textDark,
      backgroundColor: AppColors.background,
    ),
    codeblockDecoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    blockquote: body(14.5, color: AppColors.textDark),
    blockquoteDecoration: BoxDecoration(
      color: AppColors.primaryPale,
      borderRadius: BorderRadius.circular(8),
      border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
    ),
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    tableHead: body(13, weight: FontWeight.w700, color: AppColors.textDark, height: 1.4),
    tableBody: body(13, height: 1.45),
    tableBorder: TableBorder.all(color: AppColors.border, width: 1),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  );
}
