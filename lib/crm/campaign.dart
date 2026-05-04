import 'package:cloud_firestore/cloud_firestore.dart';

/// 施策（Campaign）= 媒体（source）を細分化した実行単位。
/// 例: 「Instagram」全体ではなく「Instagram_Reel_教具紹介_2026Q2」のように、
///     ROI 測定の最小単位として扱う。
///
/// 既存 plus_families.children[].source は破壊しない。Campaign 未紐付けの Lead は
/// 引き続き source（媒体）のみで管理され、媒体別 KPI 集計には反映される。
class Campaign {
  final String id;
  final String businessId; // F2 では 'Plus' 固定。将来 'BS' を追加。
  final String name;
  final String channel; // CrmOptions.sources の id（'instagram' / 'website' / ...）
  final CampaignType type;
  final num? cost; // null = 計上対象外（organic 等）。CAC 算出不可。
  final DateTime startDate;
  final DateTime? endDate; // null = 進行中
  final String hypothesis;
  final int expectedLeads;
  final int expectedConversions;
  final CampaignStatus status;
  final String? retrospective; // F9 で AI 生成
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;

  Campaign({
    required this.id,
    required this.businessId,
    required this.name,
    required this.channel,
    required this.type,
    required this.cost,
    required this.startDate,
    required this.endDate,
    required this.hypothesis,
    required this.expectedLeads,
    required this.expectedConversions,
    required this.status,
    required this.retrospective,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
  });

  factory Campaign.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return Campaign(
      id: doc.id,
      businessId: (d['businessId'] as String?) ?? 'Plus',
      name: (d['name'] as String?) ?? '',
      channel: (d['channel'] as String?) ?? 'other',
      type: CampaignTypeX.fromId(d['type'] as String?),
      cost: d['cost'] is num ? d['cost'] as num : null,
      startDate: (d['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (d['endDate'] as Timestamp?)?.toDate(),
      hypothesis: (d['hypothesis'] as String?) ?? '',
      expectedLeads: (d['expectedLeads'] as num?)?.toInt() ?? 0,
      expectedConversions: (d['expectedConversions'] as num?)?.toInt() ?? 0,
      status: CampaignStatusX.fromId(d['status'] as String?),
      retrospective: d['retrospective'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      createdBy: d['createdBy'] as String?,
    );
  }

  Map<String, dynamic> toCreateMap({required String createdBy}) {
    final now = FieldValue.serverTimestamp();
    return {
      'businessId': businessId,
      'name': name,
      'channel': channel,
      'type': type.id,
      'cost': cost,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': endDate == null ? null : Timestamp.fromDate(endDate!),
      'hypothesis': hypothesis,
      'expectedLeads': expectedLeads,
      'expectedConversions': expectedConversions,
      'status': status.id,
      'retrospective': retrospective,
      'createdAt': now,
      'updatedAt': now,
      'createdBy': createdBy,
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'businessId': businessId,
      'name': name,
      'channel': channel,
      'type': type.id,
      'cost': cost,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': endDate == null ? null : Timestamp.fromDate(endDate!),
      'hypothesis': hypothesis,
      'expectedLeads': expectedLeads,
      'expectedConversions': expectedConversions,
      'status': status.id,
      'retrospective': retrospective,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Campaign copyWith({
    String? name,
    String? channel,
    CampaignType? type,
    num? cost,
    bool clearCost = false,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    String? hypothesis,
    int? expectedLeads,
    int? expectedConversions,
    CampaignStatus? status,
    String? retrospective,
  }) {
    return Campaign(
      id: id,
      businessId: businessId,
      name: name ?? this.name,
      channel: channel ?? this.channel,
      type: type ?? this.type,
      cost: clearCost ? null : (cost ?? this.cost),
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      hypothesis: hypothesis ?? this.hypothesis,
      expectedLeads: expectedLeads ?? this.expectedLeads,
      expectedConversions: expectedConversions ?? this.expectedConversions,
      status: status ?? this.status,
      retrospective: retrospective ?? this.retrospective,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: createdBy,
    );
  }
}

enum CampaignStatus { planning, running, reviewing, archived }

extension CampaignStatusX on CampaignStatus {
  String get id {
    switch (this) {
      case CampaignStatus.planning:
        return 'planning';
      case CampaignStatus.running:
        return 'running';
      case CampaignStatus.reviewing:
        return 'reviewing';
      case CampaignStatus.archived:
        return 'archived';
    }
  }

  String get label {
    switch (this) {
      case CampaignStatus.planning:
        return 'プランニング';
      case CampaignStatus.running:
        return '実行中';
      case CampaignStatus.reviewing:
        return 'レビュー中';
      case CampaignStatus.archived:
        return 'アーカイブ';
    }
  }

  static CampaignStatus fromId(String? id) {
    switch (id) {
      case 'running':
        return CampaignStatus.running;
      case 'reviewing':
        return CampaignStatus.reviewing;
      case 'archived':
        return CampaignStatus.archived;
      case 'planning':
      default:
        return CampaignStatus.planning;
    }
  }
}

enum CampaignType { organic, paid, referral, event, content }

extension CampaignTypeX on CampaignType {
  String get id {
    switch (this) {
      case CampaignType.organic:
        return 'organic';
      case CampaignType.paid:
        return 'paid';
      case CampaignType.referral:
        return 'referral';
      case CampaignType.event:
        return 'event';
      case CampaignType.content:
        return 'content';
    }
  }

  String get label {
    switch (this) {
      case CampaignType.organic:
        return 'オーガニック';
      case CampaignType.paid:
        return '広告';
      case CampaignType.referral:
        return '紹介';
      case CampaignType.event:
        return 'イベント';
      case CampaignType.content:
        return 'コンテンツ';
    }
  }

  static CampaignType fromId(String? id) {
    switch (id) {
      case 'paid':
        return CampaignType.paid;
      case 'referral':
        return CampaignType.referral;
      case 'event':
        return CampaignType.event;
      case 'content':
        return CampaignType.content;
      case 'organic':
      default:
        return CampaignType.organic;
    }
  }
}

/// クライアント側で集計するヘルパー。Cloud Functions の自動集計は F6 で導入予定。
/// 入力は `LeadView.data()` の Map を期待。
class CampaignMetrics {
  final int actualLeads;
  final int actualConversions;
  final num? cac; // cost null or actualConversions=0 の場合は null
  final double? conversionRate; // %

  const CampaignMetrics({
    required this.actualLeads,
    required this.actualConversions,
    required this.cac,
    required this.conversionRate,
  });

  static CampaignMetrics compute({
    required String campaignId,
    required num? cost,
    required Iterable<Map<String, dynamic>> leadData,
  }) {
    var leads = 0;
    var conversions = 0;
    for (final d in leadData) {
      if ((d['sourceCampaignId'] as String?) != campaignId) continue;
      leads++;
      if ((d['stage'] as String?) == 'won') {
        conversions++;
      }
    }
    final cac = (cost == null || conversions == 0) ? null : cost / conversions;
    final cvr = leads == 0 ? null : (conversions / leads) * 100.0;
    return CampaignMetrics(
      actualLeads: leads,
      actualConversions: conversions,
      cac: cac,
      conversionRate: cvr,
    );
  }
}
