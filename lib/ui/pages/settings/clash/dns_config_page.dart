import 'package:TorBox/ui/constants/spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:TorBox/providers/content_provider.dart';
import 'package:TorBox/i18n/i18n.dart';
import 'package:TorBox/ui/widgets/setting/dns_config_card.dart';
import 'package:TorBox/services/log_print_service.dart';

class DnsConfigPage extends StatefulWidget {
  const DnsConfigPage({super.key});

  @override
  State<DnsConfigPage> createState() => _DnsConfigPageState();
}

class _DnsConfigPageState extends State<DnsConfigPage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    Logger.info('初始化 DnsConfigPage');
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ContentProvider>(context, listen: false);
    final theme = Theme.of(context);
    final trans = context.translate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 自定义标题栏
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    provider.switchView(ContentView.settingsClashFeatures),
              ),
              const SizedBox(width: 8),
              Text(
                trans.clash_features.dns_config.page_title,
                style: theme.textTheme.titleLarge,
              ),
            ],
          ),
        ),
        // 可滚动内容
        Expanded(
          child: Padding(
            padding: SpacingConstants.scrollbarPadding,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                32,
                16,
                32 - SpacingConstants.scrollbarRightCompensation,
                16,
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [DnsConfigCard(key: ValueKey('dns_config'))],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
