import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:TorBox/ui/widgets/home/outbound_mode_card.dart';
import 'package:TorBox/ui/widgets/home/proxy_switch_card.dart';
import 'package:provider/provider.dart';
import 'package:TorBox/clash/model/traffic_data_model.dart';
import 'package:TorBox/clash/providers/clash_provider.dart';
import 'package:TorBox/clash/providers/traffic_provider.dart';
import 'package:TorBox/ui/widgets/home/running_status_card.dart';
import 'package:TorBox/ui/widgets/home/traffic_speed_card.dart';
import 'package:TorBox/ui/widgets/home/tun_mode_card.dart';
import 'package:TorBox/services/log_print_service.dart';
import 'package:TorBox/ui/constants/spacing.dart';

// 主页 - 代理控制中心
class HomePageContent extends StatefulWidget {
  const HomePageContent({super.key});

  @override
  State<HomePageContent> createState() => _HomePageContentState();
}

class _HomePageContentState extends State<HomePageContent> {
  @override
  void initState() {
    super.initState();
    Logger.info('初始化 HomePageContent');
  }

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobilePlatform =
            !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS);
        final shouldShowTunCard = !isMobilePlatform;

        final isCompactLayout = constraints.maxWidth < 600;
        final horizontalPadding = isCompactLayout ? 16.0 : 25.0;
        final sectionSpacing = isCompactLayout ? 16.0 : 24.0;
        final cardSpacing = isCompactLayout ? 16.0 : 25.0;

        return Padding(
          padding: SpacingConstants.scrollbarPadding,
          child: SingleChildScrollView(
            controller: scrollController,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    constraints.maxHeight -
                    SpacingConstants.scrollbarPaddingTop -
                    SpacingConstants.scrollbarPaddingBottom,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  // 抵消外层滚动条上边距，避免内容刚好溢出触发滚动抖动
                  (isCompactLayout ? 16.0 : 24.0) -
                      SpacingConstants.scrollbarPaddingTop,
                  horizontalPadding -
                      SpacingConstants.scrollbarRightCompensation,
                  8.0, // 距底2px
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    // 第一行：左侧(代理+TUN) + 右侧(出站模式)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 左侧两块垂直排列
                          Expanded(
                            child: Column(
                              children: [
                                // 左侧(代理+TUN)
                                Expanded(child: ProxySwitchCard()),
                                const SizedBox(height: 4), // 垂直间距
                                // 右侧(出站模式)
                                Expanded(child: TunModeCard()),
                              ],
                            ),
                          ),
                          const SizedBox(width: 18), // 左右间距
                          // 右侧出站模式
                          Expanded(child: OutboundModeCard()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    // 第二行：网速流量卡片（占据整行）
                    _buildTrafficSection(context),
                    const SizedBox(height: 20),
                    // 第三行：运行状态卡片（占据整行）
                    Expanded(child: RunningStatusCard()),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrafficSection(BuildContext context) {
    final trafficProvider = context.read<TrafficProvider>();
    final isCoreRunning = context.select<ClashProvider, bool>(
      (m) => m.isCoreRunning,
    );

    return isCoreRunning
        ? StreamBuilder<TrafficData>(
            stream: context.read<ClashProvider>().trafficStream,
            builder: (context, snapshot) {
              final traffic = snapshot.data ?? TrafficData.zero;
              final trafficWithTotal = traffic.copyWithTotal(
                totalUpload: trafficProvider.totalUpload,
                totalDownload: trafficProvider.totalDownload,
              );
              return TrafficSpeedCard(
                traffic: trafficWithTotal,
                isCoreRunning: isCoreRunning,
                onReset: trafficProvider.resetTotalTraffic,
              );
            },
          )
        : TrafficSpeedCard(
            traffic: trafficProvider.lastTrafficData ?? TrafficData.zero,
            isCoreRunning: isCoreRunning,
            onReset: trafficProvider.resetTotalTraffic,
          );
  }
}
