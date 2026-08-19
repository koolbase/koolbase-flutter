/// Models for Koolbase Fiscal — jurisdiction-neutral by design.
///
/// The SDK never learns a jurisdiction's vocabulary: payloads travel as
/// maps shaped by the device's adapter (see the adapter's docs for the
/// exact fields), and the certification comes back as the authority
/// granted it (Ghana: `ysdcregsig`, `ysdcrecnum`, `qr_code`, ...).
library;

import '../koolbase_exception.dart';

/// The lifecycle status of a fiscal intent.
///
/// A sale is durably recorded the moment `submit` returns; fiscal
/// numbers and the authority's certification follow the state machine:
///
/// - [queued] / [submitting] / [retrying]: sealed with allocated
///   numbers; delivery to the authority is in progress.
/// - [fiscalized]: the authority answered; for certifying document
///   kinds the [FiscalIntentResult.certification] is present.
/// - [blocked]: a precondition failed BEFORE any fiscal number was
///   consumed (see [FiscalIntentResult.blockedReason]). Resubmitting
///   the same `clientRef` after fixing the cause resumes it.
/// - [attention]: the authority rejected the document, or its
///   credential died after sealing. An operator resolves it; the
///   register's chain waits behind it.
/// - [voided]: terminally closed by an operator without fiscalization.
enum FiscalStatus {
  created,
  blocked,
  queued,
  submitting,
  retrying,
  fiscalized,
  attention,
  voided,
  unknown;

  static FiscalStatus parse(String? raw) {
    for (final s in FiscalStatus.values) {
      if (s.name == raw) return s;
    }
    return FiscalStatus.unknown;
  }
}

/// The result of a fiscal submission or status poll.
class FiscalIntentResult {
  /// Koolbase's durable identity for this intent.
  final String intentId;

  /// Current lifecycle status.
  final FiscalStatus status;

  /// Why a [FiscalStatus.blocked] intent cannot proceed
  /// (e.g. `credential_missing`, `device_not_active`). Null otherwise.
  final String? blockedReason;

  /// The allocated fiscal numbers (e.g. `{"INV": 501}`). Present once
  /// sealed; absent while blocked — a blocked intent has consumed
  /// nothing.
  final Map<String, int>? numbers;

  /// When the document was sealed (immutable from this moment).
  final DateTime? sealedAt;

  /// What the authority granted, exactly as it granted it —
  /// adapter-shaped. For Ghana (gh-gra): `ysdcregsig` (signature),
  /// `ysdcrecnum` (receipt number), `qr_code` (verification URL to
  /// render as a QR image), timestamps and SDC identity.
  ///
  /// Present only when [status] is [FiscalStatus.fiscalized] AND the
  /// document kind certifies (a purchase record, for example, is
  /// acknowledged without certification by design).
  final Map<String, dynamic>? certification;

  const FiscalIntentResult({
    required this.intentId,
    required this.status,
    this.blockedReason,
    this.numbers,
    this.sealedAt,
    this.certification,
  });

  /// True once the authority has certified this document — the moment
  /// a receipt may legally carry the fiscal marks.
  bool get isFiscalized => status == FiscalStatus.fiscalized;

  /// True while the intent is sealed and travelling to the authority.
  bool get isPending =>
      status == FiscalStatus.queued ||
      status == FiscalStatus.submitting ||
      status == FiscalStatus.retrying;

  factory FiscalIntentResult.fromJson(Map<String, dynamic> json) {
    return FiscalIntentResult(
      intentId: json['intent_id'] as String? ?? '',
      status: FiscalStatus.parse(json['status'] as String?),
      blockedReason: json['blocked_reason'] as String?,
      numbers: (json['numbers'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toInt())),
      sealedAt: json['sealed_at'] != null
          ? DateTime.tryParse(json['sealed_at'] as String)
          : null,
      certification: json['certification'] as Map<String, dynamic>?,
    );
  }
}

/// Thrown when a fiscal operation fails for non-auth reasons: network
/// errors, malformed responses, or server-side refusals. Carries the
/// HTTP status when one was received.
class FiscalException extends KoolbaseException {
  final int? statusCode;
  const FiscalException(super.message, {this.statusCode});
}
