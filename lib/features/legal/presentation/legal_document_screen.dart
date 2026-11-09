import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/design_components.dart';
import '../../../shared/widgets/responsive_page.dart';

enum LegalDocumentType { privacy, terms }

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({required this.type, super.key});

  final LegalDocumentType type;

  @override
  Widget build(BuildContext context) {
    final privacy = type == LegalDocumentType.privacy;
    final title = privacy ? 'Privacy policy' : 'Terms of service';
    final sections = privacy ? _privacySections : _termsSections;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(title),
      ),
      body: ResponsivePage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'DRAFT — REQUIRES LEGAL REVIEW',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    privacy
                        ? 'This draft describes verified behavior in the current application. Privacy, retention, and deletion policies are not finalized; this is not a production privacy notice.'
                        : 'This draft is a product review aid, not approved terms of service. Legal terms and service conditions have not been adopted.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
            for (final section in sections) ...[
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        section.$1,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(section.$2),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
            Text(
              'Twogethera · draft for product and legal review',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class LegalDocumentLinks extends StatelessWidget {
  const LegalDocumentLinks({super.key});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      TextButton.icon(
        onPressed: () => context.push('/privacy'),
        icon: const Icon(Icons.privacy_tip_outlined),
        label: const Text('Privacy policy draft'),
      ),
      TextButton.icon(
        onPressed: () => context.push('/terms'),
        icon: const Icon(Icons.description_outlined),
        label: const Text('Terms draft'),
      ),
    ],
  );
}

const _privacySections = <(String, String)>[
  (
    'Account and profile information',
    'Sign-in uses Supabase Auth. A personal profile can contain a display name and a private About Me note. The linked partner can see the display name; the About Me note is owner-only. Profile photos are disabled in Private Beta V1.',
  ),
  (
    'Shared couple information',
    'Active partners can access shared planner items, dates, plans, tasks, date-night ideas and votes, goals and milestones, and budget entries. Memories and file attachments are unavailable in Private Beta V1. Shared access is enforced by server-side membership checks and database policies.',
  ),
  (
    'Personal preferences',
    'Appearance and dashboard preferences are stored on the individual account. They are not couple-wide settings and are protected by owner-only database access.',
  ),
  (
    'File storage',
    'Profile photos, memory photos, and budget receipt attachments are disabled in Private Beta V1. The app does not upload or download files.',
  ),
  (
    'Retention, unlinking, and account deletion',
    'Shared-content retention, archive access, privacy removal, and complete account-deletion procedures are not finalized. The app provides an account-deletion request control, but processing and removal are subject to those procedures. This draft makes no promise of indefinite retention or immediate physical erasure.',
  ),
  (
    'Before public launch',
    'A final notice still needs approved retention and deletion policies, a verified support contact, the responsible legal entity, and applicable jurisdiction-specific review. No company address or contact details are supplied in this draft.',
  ),
];

const _termsSections = <(String, String)>[
  (
    'What the application does',
    'Twogethera provides personal account features and shared planning tools for linked partners. Shared content is visible to active members of the couple space according to server-side access controls.',
  ),
  (
    'Your account and shared content',
    'Use an account you control. Information you add to shared planner, goal, budget, or date-night features may be visible to your active partner. Memories and file attachments are unavailable in Private Beta V1. Personal profile notes and appearance settings are kept in account-owned records.',
  ),
  (
    'Budget features',
    'Budget screens store expense amounts and partner splits as records in the app. Twogethera does not execute payments or move money. These screens are not a financial, tax, or investment service.',
  ),
  (
    'Service terms not yet defined',
    'Eligibility, account suspension and appeals, fees, warranties, liability, dispute handling, governing law, notices, and termination terms have not been approved. This document does not create or claim those terms.',
  ),
  (
    'Review required',
    'A final Terms of Service requires approval by the product owner and legal review before public production use. This draft does not identify a legal entity, address, contact email, or governing jurisdiction.',
  ),
];
