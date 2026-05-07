import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_theme.dart';
import '../crm_lead_screen.dart' show CrmOptions;
import '../services/crm_lead_adapter.dart';
import 'campaign.dart';
import 'campaign_form_dialog.dart';

/// 分析タブの中に挿入する Campaign カンバンセクション。
/// docs は親（_CrmDashboardView）が既に購読している plus_families 由来の Lead 群。
/// CampaignMetrics で Campaign 単位の集計をクライアント側で実行する。
class CampaignSection extends StatelessWidget {
  final List<LeadView> docs;
  const CampaignSection({super.key, required this.docs});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // composite index 不要にするため orderBy はサーバーで掛けず、
      // クライアント側で updatedAt 降順にソートする（Campaign 件数は少ない想定）。
      stream: FirebaseFirestore.instance
          .collection('campaigns')
          .where('businessId', isEqualTo: 'Plus')
          .snapshots(),
      builder: (context, snap) {
        // F2: rules 未デプロイ時は permission-denied で読み取り拒否されるが、
        // 他のダッシュボードセクションを使えるように静かに空状態で扱う。
        // rules デプロイ後に正常表示される。
        final isPermDenied = snap.hasError &&
            snap.error.toString().contains('permission-denied');
        if (snap.hasError && !isPermDenied) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('施策の読み込みエラー: ${snap.error}',
                style: TextStyle(color: context.colors.textSecondary)),
          );
        }
        final campaigns = isPermDenied
            ? <Campaign>[]
            : (snap.data?.docs ?? [])
                .map((d) => Campaign.fromDoc(d))
                .toList()
          ..sort((a, b) {
            final aT = a.updatedAt ?? a.createdAt ?? a.startDate;
            final bT = b.updatedAt ?? b.createdAt ?? b.startDate;
            return bT.compareTo(aT);
          });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('施策（Campaign）',
                      style: TextStyle(
                          fontSize: AppTextSize.titleSm,
                          fontWeight: FontWeight.bold)),
                ),
                if (campaigns.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('新規施策'),
                    onPressed: () => _openForm(context, null),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (campaigns.isEmpty)
              _EmptyState(
                onCreate: () => _openForm(context, null),
                rulesNotDeployed: isPermDenied,
              )
            else
              _Kanban(campaigns: campaigns, docs: docs),
          ],
        );
      },
    );
  }

  Future<void> _openForm(BuildContext context, Campaign? existing) async {
    await showDialog(
      context: context,
      builder: (_) => CampaignFormDialog(existing: existing),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  final bool rulesNotDeployed;
  const _EmptyState({
    required this.onCreate,
    this.rulesNotDeployed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.borderMedium),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.campaign_outlined,
                size: 40, color: context.colors.iconMuted),
            const SizedBox(height: 8),
            Text('まだ施策がありません',
                style: TextStyle(
                    fontSize: AppTextSize.body,
                    color: context.colors.textSecondary)),
            const SizedBox(height: 4),
            Text('「Instagram_Reel_教具紹介_2026Q2」のように施策単位で ROI を追跡できます',
                style: TextStyle(
                    fontSize: AppTextSize.small,
                    color: context.colors.textTertiary),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('最初の施策を起案'),
              onPressed: onCreate,
            ),
            if (rulesNotDeployed) ...[
              const SizedBox(height: 12),
              Text(
                  '⚠️ campaigns コレクションの読み取り権限がありません。'
                  '`firebase deploy --only firestore:rules` を実行してください。',
                  style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: AppColors.warning),
                  textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

class _Kanban extends StatelessWidget {
  final List<Campaign> campaigns;
  final List<LeadView> docs;
  const _Kanban({required this.campaigns, required this.docs});

  @override
  Widget build(BuildContext context) {
    final leadData = docs.map((d) => d.data()).toList();
    final byStatus = <CampaignStatus, List<Campaign>>{
      for (final s in CampaignStatus.values) s: <Campaign>[],
    };
    for (final c in campaigns) {
      byStatus[c.status]!.add(c);
    }
    return SizedBox(
      height: 320,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: CampaignStatus.values.map((s) {
            final list = byStatus[s]!;
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _Column(
                  status: s, campaigns: list, leadData: leadData),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _Column extends StatelessWidget {
  final CampaignStatus status;
  final List<Campaign> campaigns;
  final List<Map<String, dynamic>> leadData;
  const _Column({
    required this.status,
    required this.campaigns,
    required this.leadData,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _statusBg(context, status),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${status.label} (${campaigns.length})',
                style: TextStyle(
                    fontSize: AppTextSize.small,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textPrimary)),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: campaigns.isEmpty
                ? Container()
                : ListView.builder(
                    itemCount: campaigns.length,
                    itemBuilder: (_, i) =>
                        _Card(campaign: campaigns[i], leadData: leadData),
                  ),
          ),
        ],
      ),
    );
  }

  Color _statusBg(BuildContext context, CampaignStatus s) {
    switch (s) {
      case CampaignStatus.planning:
        return context.colors.scaffoldBgAlt;
      case CampaignStatus.running:
        return AppColors.success.withValues(alpha: 0.18);
      case CampaignStatus.reviewing:
        return AppColors.warning.withValues(alpha: 0.18);
      case CampaignStatus.archived:
        return context.colors.borderMedium;
    }
  }
}

class _Card extends StatelessWidget {
  final Campaign campaign;
  final List<Map<String, dynamic>> leadData;
  const _Card({required this.campaign, required this.leadData});

  String _channelLabel() {
    final src = CrmOptions.sources.firstWhere(
      (s) => s.id == campaign.channel,
      orElse: () => (id: 'other', label: 'その他'),
    );
    return src.label;
  }

  @override
  Widget build(BuildContext context) {
    final m = CampaignMetrics.compute(
      campaignId: campaign.id,
      cost: campaign.cost,
      leadData: leadData,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.borderMedium),
      ),
      child: InkWell(
        onTap: () => showDialog(
          context: context,
          builder: (_) => CampaignFormDialog(existing: campaign),
        ),
        onLongPress: () => _showStatusMenu(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(campaign.name,
                style: const TextStyle(
                    fontSize: AppTextSize.body,
                    fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
                '${_channelLabel()} ・ ${campaign.type.label}'
                ' ・ ${_dateRange()}',
                style: TextStyle(
                    fontSize: AppTextSize.caption,
                    color: context.colors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Row(
              children: [
                _metric('Lead', '${m.actualLeads}'),
                _metric('入会', '${m.actualConversions}'),
                _metric(
                    'CAC',
                    m.cac == null
                        ? '-'
                        : '¥${NumberFormat('#,##0').format(m.cac)}'),
                _metric(
                    'CVR',
                    m.conversionRate == null
                        ? '-'
                        : '${m.conversionRate!.toStringAsFixed(1)}%'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: AppTextSize.body,
                  fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(fontSize: AppTextSize.caption)),
        ],
      ),
    );
  }

  String _dateRange() {
    final s = DateFormat('M/d').format(campaign.startDate);
    if (campaign.endDate == null) return '$s〜';
    return '$s〜${DateFormat('M/d').format(campaign.endDate!)}';
  }

  Future<void> _showStatusMenu(BuildContext context) async {
    final next = await showModalBottomSheet<CampaignStatus>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: CampaignStatus.values
              .where((s) => s != campaign.status)
              .map((s) => ListTile(
                    leading: const Icon(Icons.swap_horiz),
                    title: Text('${s.label} に変更'),
                    onTap: () => Navigator.pop(context, s),
                  ))
              .toList(),
        ),
      ),
    );
    if (next != null) {
      await FirebaseFirestore.instance
          .collection('campaigns')
          .doc(campaign.id)
          .update({
        'status': next.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }
}
