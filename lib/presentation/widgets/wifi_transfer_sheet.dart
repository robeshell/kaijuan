import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/kaijuan_icons.dart';
import '../../core/theme.dart';
import '../../library/import/import_models.dart';
import '../../library/import/wifi_transfer_service.dart';
import 'app_components.dart';
import 'app_overlays.dart';

class WifiTransferSheet extends StatefulWidget {
  const WifiTransferSheet({super.key, required this.service});

  final WifiTransferService service;

  @override
  State<WifiTransferSheet> createState() => _WifiTransferSheetState();
}

class _WifiTransferSheetState extends State<WifiTransferSheet> {
  bool _copyNoticeVisible = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.service,
      builder: (context, _) {
        final service = widget.service;
        final url = service.url;
        final progress = service.progress;
        final queue = service.queue;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.appDivider,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'WiFi 传书',
                          style: TextStyle(
                            color: context.appPrimaryText,
                            fontSize: context.appSectionTitleSize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      AppIconButton(
                        icon: KaijuanIcons.close,
                        tooltip: '关闭',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '在同一 WiFi 下，用电脑或另一台设备打开下面的地址。',
                    style: TextStyle(color: context.appSecondaryText),
                  ),
                  const SizedBox(height: 18),
                  if (url != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: context.appDivider),
                      ),
                      child: QrImageView(
                        data: url,
                        size: 190,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppGlassSurface(
                      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                      borderRadius: BorderRadius.circular(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              url,
                              style: TextStyle(
                                color: context.appPrimaryText,
                                fontSize: context.appLabelSize,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          AppIconButton(
                            icon: KaijuanIcons.copy,
                            tooltip: '复制地址',
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: url));
                              if (mounted) {
                                setState(() => _copyNoticeVisible = true);
                                showAppSnackBar(this.context, '已复制传输地址');
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    if (_copyNoticeVisible)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6, right: 8),
                          child: Text(
                            '已复制传输地址',
                            style: TextStyle(
                              color: context.appColors.primary,
                              fontSize: context.appCaptionSize,
                            ),
                          ),
                        ),
                      ),
                  ] else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 56),
                      child: CircularProgressIndicator(),
                    ),
                  const SizedBox(height: 16),
                  if (service.phase == WifiTransferPhase.receiving ||
                      service.phase == WifiTransferPhase.importing) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        service.phase == WifiTransferPhase.importing
                            ? '正在识别并导入'
                            : '正在接收 ${service.currentFileName ?? ''}',
                        style: TextStyle(
                          color: context.appPrimaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 8),
                  ],
                  if (queue.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _TransferQueueList(items: queue),
                    const SizedBox(height: 8),
                  ],
                  if (service.phase == WifiTransferPhase.completed)
                    _StatusText(
                      text: _resultLabel(
                        queue.isEmpty
                            ? service.lastResult
                            : service.queueResult,
                      ),
                      color: context.appColors.primary,
                    ),
                  if (service.phase == WifiTransferPhase.failed)
                    _StatusText(
                      text: service.error ?? '传输或导入失败',
                      color: context.appColors.error,
                    ),
                  Text(
                    '链接将在 ${_expiresIn(service.expiresAt)} 后失效。',
                    style: TextStyle(
                      color: context.appMutedText,
                      fontSize: context.appCaptionSize,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _resultLabel(ImportResult? result) {
    if (result == null) return '传输完成';
    final total = result.added + result.updated;
    if (result.failures.isEmpty) return '已导入 $total 本';
    return '已导入 $total 本，失败 ${result.failures.length} 本';
  }

  String _expiresIn(DateTime? expiresAt) {
    if (expiresAt == null) return '稍后';
    final seconds = expiresAt
        .difference(DateTime.now())
        .inSeconds
        .clamp(0, 3600);
    final minutes = (seconds / 60).ceil();
    return '$minutes 分钟';
  }
}

class _TransferQueueList extends StatelessWidget {
  const _TransferQueueList({required this.items});

  final List<WifiTransferQueueItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '传输队列 · ${items.length}',
            style: TextStyle(
              color: context.appPrimaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final item in items) ...[
          AppGlassSurface(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                Icon(
                  _iconFor(item.phase),
                  size: 17,
                  color: _colorFor(context, item.phase),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    item.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.appPrimaryText,
                      fontSize: context.appListTitleSize,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _labelFor(item.phase),
                  style: TextStyle(
                    color: _colorFor(context, item.phase),
                    fontSize: context.appCaptionSize,
                  ),
                ),
              ],
            ),
          ),
          if (item.phase == WifiTransferItemPhase.receiving &&
              item.progress != null) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(value: item.progress),
          ],
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  IconData _iconFor(WifiTransferItemPhase phase) => switch (phase) {
    WifiTransferItemPhase.queued => Icons.schedule_outlined,
    WifiTransferItemPhase.receiving => Icons.sync,
    WifiTransferItemPhase.importing => Icons.downloading_outlined,
    WifiTransferItemPhase.completed => Icons.check_circle_outline,
    WifiTransferItemPhase.failed => Icons.error_outline,
  };

  Color _colorFor(BuildContext context, WifiTransferItemPhase phase) =>
      switch (phase) {
        WifiTransferItemPhase.completed => context.appColors.primary,
        WifiTransferItemPhase.failed => context.appColors.error,
        WifiTransferItemPhase.receiving ||
        WifiTransferItemPhase.importing => context.appColors.primary,
        WifiTransferItemPhase.queued => context.appMutedText,
      };

  String _labelFor(WifiTransferItemPhase phase) => switch (phase) {
    WifiTransferItemPhase.queued => '等待传输',
    WifiTransferItemPhase.receiving => '传输中',
    WifiTransferItemPhase.importing => '导入中',
    WifiTransferItemPhase.completed => '已完成',
    WifiTransferItemPhase.failed => '失败',
  };
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: TextStyle(color: color)),
      ),
    );
  }
}
