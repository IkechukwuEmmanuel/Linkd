/// Domain entities for Linkd app

class User {
  final int id;
  final String email;
  final DateTime createdAt;

  User({
    required this.id,
    required this.email,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      email: json['email'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'created_at': createdAt.toIso8601String(),
  };
}

class Persona {
  final int id;
  final int? userId;
  final String label;
  final double weight;
  final double? confidenceScore;
  final DateTime? createdAt;
  final List<String>? feedbackHistory;

  Persona({
    required this.id,
    this.userId,
    required this.label,
    required this.weight,
    this.confidenceScore,
    this.createdAt,
    this.feedbackHistory,
  });

  factory Persona.fromJson(Map<String, dynamic> json) {
    return Persona(
      id: json['id'],
      userId: json['user_id'],
      label: json['label'],
      weight: (json['weight'] is num) ? (json['weight'] as num).toDouble() : (json['weight'] ?? 1).toDouble(),
      confidenceScore: (json['confidence_score'] as num?)?.toDouble(),
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'label': label,
    'weight': weight,
    'confidence_score': confidenceScore,
  };

  Persona copyWith({
    int? id,
    int? userId,
    String? label,
    double? weight,
    double? confidenceScore,
    DateTime? createdAt,
  }) {
    return Persona(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      label: label ?? this.label,
      weight: weight ?? this.weight,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class Synapse {
  final int personaId;
  final String personaLabel;
  final double similarity;
  final int rank;

  Synapse({
    required this.personaId,
    required this.personaLabel,
    required this.similarity,
    required this.rank,
  });

  factory Synapse.fromJson(Map<String, dynamic> json) {
    return Synapse(
      personaId: json['persona_id'],
      personaLabel: json['persona_label'],
      similarity: (json['similarity'] as num).toDouble(),
      rank: json['rank'],
    );
  }

  Map<String, dynamic> toJson() => {
    'persona_id': personaId,
    'persona_label': personaLabel,
    'similarity': similarity,
    'rank': rank,
  };
}

class Interaction {
  final int id;
  final int userId;
  final String mode; // "live" or "recap"
  final String? transcriptExcerpt;
  final List<Synapse>? topSynapses;
  final DateTime createdAt;
  final String? extractedInterests;

  Interaction({
    required this.id,
    required this.userId,
    required this.mode,
    this.transcriptExcerpt,
    this.topSynapses,
    required this.createdAt,
    this.extractedInterests,
  });

  factory Interaction.fromJson(Map<String, dynamic> json) {
    return Interaction(
      id: json['id'],
      userId: json['user_id'],
      mode: json['mode'],
      transcriptExcerpt: json['transcript_excerpt'],
      topSynapses: (json['top_synapses'] as List?)
          ?.map((e) => Synapse.fromJson(e))
          .toList(),
      createdAt: DateTime.parse(json['created_at']),
      extractedInterests: json['extracted_interests'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'mode': mode,
    'transcript_excerpt': transcriptExcerpt,
    'top_synapses': topSynapses?.map((e) => e.toJson()).toList(),
    'created_at': createdAt.toIso8601String(),
    'extracted_interests': extractedInterests,
  };
}

class Job {
  final String id;
  final String status; // "pending", "processing", "completed", "failed"
  final int progress; // 0-100
  final String jobType; // "onboarding", "interaction"
  final dynamic result;
  final String? errorMessage;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  Job({
    required this.id,
    required this.status,
    required this.progress,
    required this.jobType,
    this.result,
    this.errorMessage,
    this.createdAt,
    this.startedAt,
    this.completedAt,
  });

  factory Job.fromJson(Map<String, dynamic> json) {
    return Job(
      id: json['job_id'],
      status: json['status'],
      progress: json['progress'] ?? 0,
      jobType: json['job_type'],
      result: json['result'],
      errorMessage: json['error_message'],
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : null,
      startedAt: json['started_at'] != null 
          ? DateTime.parse(json['started_at']) 
          : null,
      completedAt: json['completed_at'] != null 
          ? DateTime.parse(json['completed_at']) 
          : null,
    );
  }

  bool get isComplete => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isProcessing => status == 'processing' || status == 'pending';
}

class Metrics {
  final int totalInteractions;
  final int totalPersonas;
  final String? topPersona;
  final double avgExtractionAccuracy;
  final double approvalRate;
  final double avgProcessingTimeMs;
  final double avgTopSimilarity;
  final int totalApproved;
  final int totalRejected;
  final double? avgInteractionLength;
  final DateTime? lastInteractionAt;

  Metrics({
    required this.totalInteractions,
    this.totalPersonas = 0,
    this.topPersona,
    required this.avgExtractionAccuracy,
    required this.approvalRate,
    required this.avgProcessingTimeMs,
    required this.avgTopSimilarity,
    required this.totalApproved,
    required this.totalRejected,
    this.avgInteractionLength,
    this.lastInteractionAt,
  });

  factory Metrics.fromJson(Map<String, dynamic> json) {
    return Metrics(
      totalInteractions: json['total_interactions'] ?? 0,
      totalPersonas: json['total_personas'] ?? 0,
      topPersona: json['top_persona'],
      avgExtractionAccuracy: (json['avg_extraction_accuracy'] as num?)?.toDouble() ?? 0.0,
      approvalRate: (json['approval_rate'] as num?)?.toDouble() ?? 0.0,
      avgProcessingTimeMs: (json['avg_processing_time_ms'] as num?)?.toDouble() ?? 0.0,
      avgTopSimilarity: (json['avg_top_similarity'] as num?)?.toDouble() ?? 0.0,
      totalApproved: json['total_approved'] ?? 0,
      totalRejected: json['total_rejected'] ?? 0,
      avgInteractionLength: (json['avg_interaction_length'] as num?)?.toDouble(),
      lastInteractionAt: json['last_interaction_at'] != null 
        ? DateTime.parse(json['last_interaction_at'])
        : null,
    );
  }
}

class AuthResponse {
  final User user;
  final String token;
  final bool isNewUser;

  AuthResponse({
    required this.user,
    required this.token,
    required this.isNewUser,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      user: User.fromJson(json['user']),
      token: json['token'],
      isNewUser: json['is_new_user'] ?? false,
    );
  }
}

class Contact {
  final int id;
  final String name;
  final String? company;
  final String? role;
  final String? email;
  final String? phone;
  final String? linkedinUrl;
  final String? eventName;
  final String? eventDate;
  final String? location;
  final String? notes;
  final List<String> interests;
  final List<String> opportunities;
  final String? summary;
  final List<String> overlapPoints;
  final double overlapScore;
  final String? followUpDraft;
  final bool followUpSent;
  final String? followUpDue;
  final bool followUpCompleted;
  final int relationshipStrength;
  final String? lastInteractionAt;
  final int interactionCount;
  final bool isStarred;
  final List<String> tags;
  final String? createdAt;
  final String? updatedAt;
  final List<ContactInteractionItem>? interactions;

  Contact({
    required this.id,
    required this.name,
    this.company,
    this.role,
    this.email,
    this.phone,
    this.linkedinUrl,
    this.eventName,
    this.eventDate,
    this.location,
    this.notes,
    this.interests = const [],
    this.opportunities = const [],
    this.summary,
    this.overlapPoints = const [],
    this.overlapScore = 0.0,
    this.followUpDraft,
    this.followUpSent = false,
    this.followUpDue,
    this.followUpCompleted = false,
    this.relationshipStrength = 1,
    this.lastInteractionAt,
    this.interactionCount = 1,
    this.isStarred = false,
    this.tags = const [],
    this.createdAt,
    this.updatedAt,
    this.interactions,
  });

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'],
      name: json['name'] ?? 'Unknown',
      company: json['company'],
      role: json['role'],
      email: json['email'],
      phone: json['phone'],
      linkedinUrl: json['linkedin_url'],
      eventName: json['event_name'],
      eventDate: json['event_date'],
      location: json['location'],
      notes: json['notes'],
      interests: List<String>.from(json['interests'] ?? []),
      opportunities: List<String>.from(json['opportunities'] ?? []),
      summary: json['summary'],
      overlapPoints: List<String>.from(json['overlap_points'] ?? []),
      overlapScore: (json['overlap_score'] as num?)?.toDouble() ?? 0.0,
      followUpDraft: json['follow_up_draft'],
      followUpSent: json['follow_up_sent'] ?? false,
      followUpDue: json['follow_up_due'],
      followUpCompleted: json['follow_up_completed'] ?? false,
      relationshipStrength: json['relationship_strength'] ?? 1,
      lastInteractionAt: json['last_interaction_at'],
      interactionCount: json['interaction_count'] ?? 1,
      isStarred: json['is_starred'] ?? false,
      tags: List<String>.from(json['tags'] ?? []),
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
      interactions: (json['interactions'] as List?)
          ?.map((e) => ContactInteractionItem.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'company': company,
    'role': role,
    'email': email,
    'phone': phone,
    'linkedin_url': linkedinUrl,
    'event_name': eventName,
    'interests': interests,
    'opportunities': opportunities,
    'summary': summary,
    'notes': notes,
    'tags': tags,
  };
}

class ContactInteractionItem {
  final int id;
  final int contactId;
  final String interactionType;
  final String? content;
  final String? recordedAt;

  ContactInteractionItem({
    required this.id,
    required this.contactId,
    required this.interactionType,
    this.content,
    this.recordedAt,
  });

  factory ContactInteractionItem.fromJson(Map<String, dynamic> json) {
    return ContactInteractionItem(
      id: json['id'],
      contactId: json['contact_id'],
      interactionType: json['interaction_type'] ?? 'unknown',
      content: json['content'],
      recordedAt: json['recorded_at'],
    );
  }
}

class InsightsSummary {
  final int totalContacts;
  final int followUpsDue;
  final int starredContacts;
  final List<Map<String, dynamic>> clusters;
  final List<Map<String, dynamic>> recentContacts;

  InsightsSummary({
    required this.totalContacts,
    required this.followUpsDue,
    required this.starredContacts,
    this.clusters = const [],
    this.recentContacts = const [],
  });

  factory InsightsSummary.fromJson(Map<String, dynamic> json) {
    return InsightsSummary(
      totalContacts: json['total_contacts'] ?? 0,
      followUpsDue: json['follow_ups_due'] ?? 0,
      starredContacts: json['starred_contacts'] ?? 0,
      clusters: List<Map<String, dynamic>>.from(json['clusters'] ?? []),
      recentContacts: List<Map<String, dynamic>>.from(json['recent_contacts'] ?? []),
    );
  }
}
