import 'audit.dart';

enum RoleConfidence {
  high('высокая'),
  medium('средняя'),
  low('низкая');

  const RoleConfidence(this.label);
  final String label;
}

class SpeakerSuggestion {
  const SpeakerSuggestion({
    required this.speaker,
    required this.role,
    required this.confidence,
    required this.reason,
    required this.evidence,
  });
  final int speaker;
  final ParticipantRole role;
  final RoleConfidence confidence;
  final String reason, evidence;

  factory SpeakerSuggestion.fromJson(Map<String, dynamic> json) =>
      SpeakerSuggestion(
        speaker: json['speaker'] as int,
        role: ParticipantRole.values.byName(json['role'] as String),
        confidence: RoleConfidence.values.byName(json['confidence'] as String),
        reason: json['reason'] as String,
        evidence: json['evidence'] as String,
      );
}

class TranscriptPreparation {
  const TranscriptPreparation({
    required this.transcript,
    required this.participants,
    required this.notice,
    required this.model,
  });
  final String transcript, notice, model;
  final List<SpeakerSuggestion> participants;

  factory TranscriptPreparation.fromJson(Map<String, dynamic> json) =>
      TranscriptPreparation(
        transcript: json['transcript'] as String,
        participants: (json['participants'] as List)
            .map(
              (item) =>
                  SpeakerSuggestion.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        notice: json['notice'] as String,
        model: json['model'] as String,
      );
}
