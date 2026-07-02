import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:TorBox/clash/model/subscription_model.dart';
import 'package:TorBox/clash/providers/subscription_provider.dart';
import 'package:TorBox/clash/services/subscription_service.dart';
import 'package:TorBox/ui/common/modern_dialog.dart';
import 'package:TorBox/ui/common/modern_dialog_subs/text_input_field.dart';
import 'package:TorBox/i18n/i18n.dart';
import 'package:yaml/yaml.dart';

class ChainProxyDialogResult {
  final List<String> builtinChainProxyNames;
  final List<String> disabledBuiltinChainProxyNames;
  final List<CustomChainProxy> customChainProxies;

  const ChainProxyDialogResult({
    required this.builtinChainProxyNames,
    required this.disabledBuiltinChainProxyNames,
    required this.customChainProxies,
  });
}

class _ChainProxyCandidate {
  final String name;
  final String type;

  const _ChainProxyCandidate({required this.name, required this.type});
}

class _ChainProxyDraft {
  final String id;
  final String displayName;
  final int hopCount;
  final List<String> selectedNodeNames;

  const _ChainProxyDraft({
    required this.id,
    required this.displayName,
    required this.hopCount,
    required this.selectedNodeNames,
  });

  _ChainProxyDraft copyWith({
    String? id,
    String? displayName,
    int? hopCount,
    List<String>? selectedNodeNames,
  }) {
    return _ChainProxyDraft(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      hopCount: hopCount ?? this.hopCount,
      selectedNodeNames: selectedNodeNames ?? this.selectedNodeNames,
    );
  }

  CustomChainProxy toCustomChainProxy() {
    return CustomChainProxy(
      id: id,
      displayName: displayName,
      nodeNames: List<String>.from(selectedNodeNames),
    );
  }
}

class ChainProxyDialog extends StatefulWidget {
  final String profileName;
  final List<String> builtinChainProxyNames;
  final List<String> disabledBuiltinChainProxyNames;
  final List<CustomChainProxy> customChainProxies;
  final bool isLocalImport;
  final String? localFilePath;
  final String? existingRemoteUrl;
  final String remoteAgeSecretKey;
  final bool isEditMode;
  final String? existingProfileName;

  const ChainProxyDialog({
    super.key,
    required this.profileName,
    required this.builtinChainProxyNames,
    required this.disabledBuiltinChainProxyNames,
    required this.customChainProxies,
    required this.isLocalImport,
    this.localFilePath,
    this.existingRemoteUrl,
    this.remoteAgeSecretKey = '',
    required this.isEditMode,
    this.existingProfileName,
  });

  static Future<ChainProxyDialogResult?> show(
    BuildContext context, {
    required String profileName,
    required List<String> builtinChainProxyNames,
    required List<String> disabledBuiltinChainProxyNames,
    required List<CustomChainProxy> customChainProxies,
    required bool isLocalImport,
    String? localFilePath,
    String? existingRemoteUrl,
    String remoteAgeSecretKey = '',
    required bool isEditMode,
    String? existingProfileName,
  }) {
    return showDialog<ChainProxyDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ChainProxyDialog(
        profileName: profileName,
        builtinChainProxyNames: builtinChainProxyNames,
        disabledBuiltinChainProxyNames: disabledBuiltinChainProxyNames,
        customChainProxies: customChainProxies,
        isLocalImport: isLocalImport,
        localFilePath: localFilePath,
        existingRemoteUrl: existingRemoteUrl,
        remoteAgeSecretKey: remoteAgeSecretKey,
        isEditMode: isEditMode,
        existingProfileName: existingProfileName,
      ),
    );
  }

  @override
  State<ChainProxyDialog> createState() => _ChainProxyDialogState();
}

class _ChainProxyDialogState extends State<ChainProxyDialog> {
  static const int _defaultHopCount = 2;

  final SubscriptionService _subscriptionService = SubscriptionService();
  final TextEditingController _nameController = TextEditingController();

  late List<String> _builtinChainProxyNames;
  late List<String> _disabledBuiltinChainProxyNames;
  late List<CustomChainProxy> _customChainProxies;
  late List<_ChainProxyDraft> _drafts;
  List<_ChainProxyCandidate> _candidates = [];
  bool _isLoadingCandidates = true;
  bool _isEditingDraft = false;
  int _activeSlotIndex = 0;
  String? _editingDraftId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _builtinChainProxyNames = List<String>.from(widget.builtinChainProxyNames);
    _disabledBuiltinChainProxyNames = List<String>.from(
      widget.disabledBuiltinChainProxyNames,
    );
    _customChainProxies = List<CustomChainProxy>.from(
      widget.customChainProxies,
    );
    _drafts = _customChainProxies
        .map(
          (item) => _ChainProxyDraft(
            id: item.id,
            displayName: item.displayName,
            hopCount: item.nodeNames.isEmpty
                ? _defaultHopCount
                : item.nodeNames.length,
            selectedNodeNames: List<String>.from(item.nodeNames),
          ),
        )
        .toList();
    _loadCandidates();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    setState(() {
      _isLoadingCandidates = true;
      _errorMessage = null;
    });

    try {
      final content = await _loadConfigContent();
      final yamlDoc = loadYaml(content);
      if (yamlDoc is! YamlMap) {
        throw Exception('配置文件不是有效的 YAML');
      }

      final proxies = yamlDoc['proxies'];
      if (proxies is! YamlList) {
        throw Exception('配置文件缺少 proxies 列表');
      }

      final builtinChainNames = <String>{};
      for (final item in proxies) {
        if (item is! YamlMap) continue;
        final name = item['name'];
        final dialerProxy = item['dialer-proxy'];
        if (name is String &&
            name.isNotEmpty &&
            dialerProxy is String &&
            dialerProxy.isNotEmpty) {
          builtinChainNames.add(name);
        }
      }

      final candidates = <_ChainProxyCandidate>[];
      for (final item in proxies) {
        if (item is! YamlMap) continue;
        final name = item['name'];
        final type = item['type'];
        if (name is! String || name.isEmpty) continue;
        if (type is! String || type.isEmpty) continue;
        if (builtinChainNames.contains(name)) continue;
        if (_customChainProxies.any((proxy) => proxy.displayName == name)) {
          continue;
        }
        candidates.add(_ChainProxyCandidate(name: name, type: type));
      }

      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _isLoadingCandidates = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoadingCandidates = false;
      });
    }
  }

  Future<String> _loadConfigContent() async {
    if (widget.isEditMode) {
      final filePath = widget.localFilePath;
      if (filePath == null || filePath.isEmpty) {
        throw Exception('当前订阅配置路径不可用');
      }
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('当前订阅配置文件不存在');
      }
      return await file.readAsString();
    }

    if (widget.isLocalImport) {
      final filePath = widget.localFilePath;
      if (filePath == null || filePath.isEmpty) {
        throw Exception('请先选择本地配置文件');
      }
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('本地配置文件不存在');
      }
      return await _subscriptionService.parseLocalFile(file.path);
    }

    final remoteUrl = widget.existingRemoteUrl?.trim();
    if (remoteUrl == null || remoteUrl.isEmpty) {
      throw Exception('请先填写订阅链接');
    }

    final subscriptionProvider = context.read<SubscriptionProvider>();
    return await subscriptionProvider.parseRemoteSubscriptionContent(
      remoteUrl,
      ageSecretKey: widget.remoteAgeSecretKey,
    );
  }

  _ChainProxyDraft _createEmptyDraft() {
    return _ChainProxyDraft(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      displayName: '',
      hopCount: _defaultHopCount,
      selectedNodeNames: const [],
    );
  }

  _ChainProxyDraft? _currentDraft() {
    final draftId = _editingDraftId;
    if (draftId == null) return null;
    for (final draft in _drafts) {
      if (draft.id == draftId) return draft;
    }
    return null;
  }

  List<String> _draftBlockedNodes(_ChainProxyDraft draft) {
    final blocked = <String>[];
    for (var i = 0; i < draft.selectedNodeNames.length; i++) {
      if (i == _activeSlotIndex) continue;
      final name = draft.selectedNodeNames[i];
      if (name.isEmpty) continue;
      blocked.add(name);
    }
    return blocked.toSet().toList();
  }

  void _enterDraftMode({_ChainProxyDraft? initialDraft}) {
    final nextDraft = initialDraft ?? _createEmptyDraft();
    setState(() {
      _isEditingDraft = true;
      _activeSlotIndex = 0;
      _editingDraftId = nextDraft.id;
      _nameController.text = nextDraft.displayName;
      if (initialDraft == null) {
        _drafts = [..._drafts, nextDraft];
      }
    });
  }

  void _exitDraftMode({bool discardDraft = false}) {
    final draftId = _editingDraftId;
    if (draftId == null) return;

    setState(() {
      if (discardDraft) {
        _drafts.removeWhere((draft) => draft.id == draftId);
      }
      _editingDraftId = null;
      _activeSlotIndex = 0;
      _isEditingDraft = false;
      _nameController.clear();
    });
  }

  void _updateDraftHopCount(int nextHopCount) {
    final draftId = _editingDraftId;
    if (draftId == null || nextHopCount < 1) return;

    setState(() {
      final index = _drafts.indexWhere((draft) => draft.id == draftId);
      if (index == -1) return;

      final current = _drafts[index];
      final nextSelectedNodeNames = List<String>.from(
        current.selectedNodeNames,
      );
      while (nextSelectedNodeNames.length > nextHopCount) {
        nextSelectedNodeNames.removeLast();
      }

      _drafts[index] = current.copyWith(
        hopCount: nextHopCount,
        selectedNodeNames: nextSelectedNodeNames,
      );
      if (_activeSlotIndex >= nextHopCount) {
        _activeSlotIndex = nextHopCount - 1;
      }
    });
  }

  void _selectDraftNode(String nodeName, int index) {
    final draftId = _editingDraftId;
    if (draftId == null) return;

    setState(() {
      final draftIndex = _drafts.indexWhere((draft) => draft.id == draftId);
      if (draftIndex == -1) return;

      final current = _drafts[draftIndex];
      final selected = List<String>.from(current.selectedNodeNames);
      while (selected.length <= index) {
        selected.add('');
      }

      if (selected[index] == nodeName) {
        selected[index] = '';
      } else {
        selected[index] = nodeName;
      }

      _drafts[draftIndex] = current.copyWith(selectedNodeNames: selected);
    });
  }

  void _toggleBuiltinChainProxy(String name) {
    setState(() {
      if (_disabledBuiltinChainProxyNames.contains(name)) {
        _disabledBuiltinChainProxyNames.remove(name);
      } else {
        _disabledBuiltinChainProxyNames.add(name);
      }
    });
  }

  void _removeCustomChainProxy(String id) {
    setState(() {
      _customChainProxies.removeWhere((item) => item.id == id);
      _drafts.removeWhere((item) => item.id == id);
    });
  }

  void _saveCurrentDraft() {
    final draft = _currentDraft();
    if (draft == null) return;

    final displayName = _nameController.text.trim();
    if (displayName.isEmpty) return;

    final selectedNodeNames = draft.selectedNodeNames
        .where((name) => name.isNotEmpty)
        .toList();
    if (selectedNodeNames.length != draft.hopCount) return;

    final nextDraft = draft.copyWith(
      displayName: displayName,
      selectedNodeNames: selectedNodeNames,
    );
    final nextItem = nextDraft.toCustomChainProxy();

    setState(() {
      _customChainProxies = [
        for (final item in _customChainProxies)
          if (item.id != nextItem.id) item,
        nextItem,
      ];
      _drafts = [
        for (final item in _drafts)
          if (item.id != nextItem.id) item,
        nextDraft,
      ];
      _editingDraftId = null;
      _activeSlotIndex = 0;
      _isEditingDraft = false;
      _nameController.clear();
    });
  }

  void _handleSave() {
    final nextCustomChainProxies = <CustomChainProxy>[];
    for (final item in _customChainProxies) {
      final draft = _drafts.firstWhere(
        (value) => value.id == item.id,
        orElse: () => _ChainProxyDraft(
          id: item.id,
          displayName: item.displayName,
          hopCount: item.nodeNames.isEmpty
              ? _defaultHopCount
              : item.nodeNames.length,
          selectedNodeNames: List<String>.from(item.nodeNames),
        ),
      );
      nextCustomChainProxies.add(draft.toCustomChainProxy());
    }

    Navigator.of(context).pop(
      ChainProxyDialogResult(
        builtinChainProxyNames: _builtinChainProxyNames,
        disabledBuiltinChainProxyNames: _disabledBuiltinChainProxyNames,
        customChainProxies: nextCustomChainProxies,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trans = context.translate.subscription_dialog;
    final currentDraft = _currentDraft();

    return ModernDialog(
      title: trans.chain_proxy_title,
      titleIcon: Icons.account_tree_outlined,
      maxWidth: 860,
      maxHeightRatio: 0.9,
      content: _buildContent(),
      actionsLeftButtons: _isEditingDraft
          ? [
              DialogActionButton(
                key: const ValueKey('subscription_chain_proxy_back_button'),
                label: trans.cancel_button,
                icon: Icons.arrow_back,
                onPressed: () => _exitDraftMode(discardDraft: true),
              ),
              DialogActionButton(
                key: const ValueKey(
                  'subscription_chain_proxy_draft_save_button',
                ),
                label: trans.save_button,
                icon: Icons.check,
                onPressed: currentDraft == null ? null : _saveCurrentDraft,
              ),
            ]
          : [
              DialogActionButton(
                key: const ValueKey('subscription_chain_proxy_add_mode_button'),
                label: trans.chain_proxy_add_button,
                icon: Icons.add,
                onPressed: _isLoadingCandidates
                    ? null
                    : () => _enterDraftMode(),
              ),
            ],
      actionsRight: [
        DialogActionButton(
          key: const ValueKey('subscription_chain_proxy_cancel_button'),
          label: trans.cancel_button,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DialogActionButton(
          key: const ValueKey('subscription_chain_proxy_save_button'),
          label: trans.save_button,
          isPrimary: true,
          onPressed: _handleSave,
        ),
      ],
      onClose: () => Navigator.of(context).pop(),
    );
  }

  Widget _buildContent() {
    if (_isLoadingCandidates) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!));
    }

    if (_isEditingDraft) {
      return _buildDraftContent();
    }

    final sections = <Widget>[];
    if (_builtinChainProxyNames.isNotEmpty) {
      sections.add(_buildBuiltinSection());
    }
    if (_customChainProxies.isNotEmpty) {
      if (sections.isNotEmpty) {
        sections.add(const SizedBox(height: 20));
      }
      sections.add(_buildCustomSection());
    }

    if (sections.isEmpty) {
      return const SizedBox(height: 120);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sections,
      ),
    );
  }

  Widget _buildDraftContent() {
    final draft = _currentDraft();
    if (draft == null) {
      return const SizedBox.shrink();
    }

    final blockedNodes = _draftBlockedNodes(draft);
    final selectedNodeNames = List<String>.from(draft.selectedNodeNames);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextInputField(
            key: const ValueKey('subscription_chain_proxy_name_field'),
            controller: _nameController,
            label: context.translate.subscription_dialog.chain_proxy_name_label,
            hint: context.translate.subscription_dialog.chain_proxy_name_hint,
            icon: Icons.label_outline,
          ),
          const SizedBox(height: 16),
          _buildHopHeader(draft),
          const SizedBox(height: 16),
          _buildSelectedPathEditor(
            draft: draft,
            selectedNodeNames: selectedNodeNames,
          ),
          const SizedBox(height: 20),
          _buildNodePool(
            selectedNodeNames: selectedNodeNames,
            blockedNodes: blockedNodes,
          ),
        ],
      ),
    );
  }

  Widget _buildHopHeader(_ChainProxyDraft draft) {
    final trans = context.translate.subscription_dialog;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.55),
      ),
      child: Row(
        children: [
          Icon(Icons.alt_route, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(trans.chain_proxy_hop_count_label),
          const Spacer(),
          IconButton(
            key: const ValueKey('subscription_chain_proxy_hop_decrease_button'),
            onPressed: draft.hopCount > 1
                ? () => _updateDraftHopCount(draft.hopCount - 1)
                : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('${draft.hopCount}', style: const TextStyle(fontSize: 16)),
          IconButton(
            key: const ValueKey('subscription_chain_proxy_hop_increase_button'),
            onPressed: () => _updateDraftHopCount(draft.hopCount + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedPathEditor({
    required _ChainProxyDraft draft,
    required List<String> selectedNodeNames,
  }) {
    final trans = context.translate.subscription_dialog;
    final slots = List.generate(draft.hopCount, (index) {
      final value = index < selectedNodeNames.length
          ? selectedNodeNames[index]
          : '';
      return value;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          trans.chain_proxy_selected_path_title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: slots.asMap().entries.map((entry) {
            final index = entry.key;
            final currentValue = entry.value;
            final isActive = _activeSlotIndex == index;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('subscription_chain_proxy_path_slot_$index'),
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() {
                    _activeSlotIndex = index;
                  });
                },
                child: Container(
                  width: 180,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: isActive ? 0.08 : 0.03)
                        : Colors.white.withValues(
                            alpha: isActive ? 0.72 : 0.45,
                          ),
                    border: Border.all(
                      color: isActive
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white.withValues(
                              alpha:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? 0.1
                                  : 0.3,
                            ),
                      width: isActive ? 1.6 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${trans.chain_proxy_path_slot_label} ${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(currentValue.isEmpty ? '-' : currentValue),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildNodePool({
    required List<String> selectedNodeNames,
    required List<String> blockedNodes,
  }) {
    final trans = context.translate.subscription_dialog;
    final activeSlotValue = _activeSlotIndex < selectedNodeNames.length
        ? selectedNodeNames[_activeSlotIndex]
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          trans.chain_proxy_candidate_title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _candidates.map((candidate) {
            final isSelected = activeSlotValue == candidate.name;
            final isBlocked =
                blockedNodes.contains(candidate.name) && !isSelected;
            return ChoiceChip(
              label: Text(candidate.name),
              selected: isSelected,
              onSelected: isBlocked
                  ? null
                  : (_) => _selectDraftNode(candidate.name, _activeSlotIndex),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBuiltinSection() {
    final trans = context.translate.subscription_dialog;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          trans.chain_proxy_builtin_title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        if (_builtinChainProxyNames.isEmpty)
          Text(trans.chain_proxy_empty)
        else
          ..._builtinChainProxyNames.map((name) {
            final enabled = !_disabledBuiltinChainProxyNames.contains(name);
            return Container(
              key: ValueKey('subscription_chain_proxy_builtin_$name'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.white.withValues(alpha: 0.4),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(name)),
                  const SizedBox(width: 12),
                  IconButton(
                    key: ValueKey(
                      'subscription_chain_proxy_builtin_toggle_$name',
                    ),
                    onPressed: () => _toggleBuiltinChainProxy(name),
                    icon: Icon(
                      enabled
                          ? Icons.block_outlined
                          : Icons.check_circle_outline,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildCustomSection() {
    final trans = context.translate.subscription_dialog;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          trans.chain_proxy_custom_title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        if (_customChainProxies.isEmpty)
          Text(trans.chain_proxy_empty)
        else
          ..._customChainProxies.map((item) {
            final chainLabel = item.nodeNames.isEmpty
                ? '-'
                : item.nodeNames.join(' → ');
            return Container(
              key: ValueKey('subscription_chain_proxy_custom_${item.id}'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.white.withValues(alpha: 0.4),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.displayName),
                        const SizedBox(height: 4),
                        Text(chainLabel),
                      ],
                    ),
                  ),
                  IconButton(
                    key: ValueKey('subscription_chain_proxy_edit_${item.id}'),
                    onPressed: () => _enterDraftMode(
                      initialDraft: _ChainProxyDraft(
                        id: item.id,
                        displayName: item.displayName,
                        hopCount: item.nodeNames.isEmpty
                            ? _defaultHopCount
                            : item.nodeNames.length,
                        selectedNodeNames: List<String>.from(item.nodeNames),
                      ),
                    ),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    key: ValueKey('subscription_chain_proxy_delete_${item.id}'),
                    onPressed: () => _removeCustomChainProxy(item.id),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
