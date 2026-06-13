import 'dart:async';
import 'dart:convert';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web/web.dart' as web;
import 'api_service.dart';

class RssReaderView extends StatefulWidget {
  const RssReaderView({super.key});

  @override
  State<RssReaderView> createState() => _RssReaderViewState();
}

class _RssReaderViewState extends State<RssReaderView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _feeds = [];
  List<dynamic> _articles = [];
  List<dynamic> _availableModels = [];
  bool _isLoadingFeeds = false;
  bool _isLoadingArticles = false;
  String? _selectedFeedFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFeeds();
    _loadArticles();
    _loadModels();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFeeds() async {
    setState(() => _isLoadingFeeds = true);
    final feeds = await ApiService.getRssFeeds();
    setState(() {
      _feeds = feeds;
      _isLoadingFeeds = false;
    });
  }

  Future<void> _loadArticles() async {
    setState(() => _isLoadingArticles = true);
    final articles = await ApiService.getRssArticles(feedId: _selectedFeedFilter);
    setState(() {
      _articles = articles;
      _isLoadingArticles = false;
    });
  }

  Future<void> _loadModels() async {
    final models = await ApiService.getModels();
    setState(() {
      _availableModels = models;
    });
  }

  Future<void> _triggerImmediateScrape(Map<String, dynamic> feed) async {
    String? selectedModelId = feed['model_id'];
    if (selectedModelId == '') selectedModelId = null;

    // Filter selectedModelId to ensure it exists in _availableModels
    if (selectedModelId != null && !_availableModels.any((m) => m['id'] == selectedModelId)) {
      selectedModelId = null;
    }

    final confirmScrape = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text("立即抓取与 AI 总结", style: TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("即将读取并解析订阅源: ${feed['name']}"),
                  const SizedBox(height: 16),
                  const Text("选择本次总结使用的 AI 模型:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedModelId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text("不使用 AI 总结 (仅抓取标题与原文)"),
                      ),
                      ..._availableModels.map((m) {
                        return DropdownMenuItem<String>(
                          value: m['id'],
                          child: Text(m['custom_name'] ?? ''),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setModalState(() {
                        selectedModelId = val;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("取消"),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("开始读取"),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmScrape != true) return;

    // Show progress dialog
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return ScrapeProgressDialog(
          feedId: feed['id'],
          feedName: feed['name'] ?? '',
          modelId: selectedModelId,
        );
      },
    );

    // Refresh UI regardless of success/background running
    _loadFeeds();
    _loadArticles();
  }

  void _showFeedDialog([Map<String, dynamic>? feed]) {
    final isEdit = feed != null;
    final nameController = TextEditingController(text: isEdit ? feed['name'] : '');
    final urlController = TextEditingController(text: isEdit ? feed['url'] : '');
    
    // Parse time
    final String initialTime = isEdit ? (feed['schedule_time'] ?? '') : '';
    final hasSchedule = initialTime.isNotEmpty;
    bool enableSchedule = hasSchedule;
    String scheduleTime = hasSchedule ? initialTime : '09:00';

    String? selectedModelId = isEdit ? feed['model_id'] : null;
    if (selectedModelId == '') selectedModelId = null;
    if (selectedModelId != null && !_availableModels.any((m) => m['id'] == selectedModelId)) {
      selectedModelId = null;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(
                isEdit ? "编辑订阅源" : "新建订阅源",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 450,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("源名称", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          hintText: "e.g., Google News World",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text("RSS Feed 链接", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: urlController,
                        decoration: const InputDecoration(
                          hintText: "https://news.google.com/rss...",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text("AI 总结模型映射", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedModelId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: "选择总结模型（不选则不进行 AI 总结）",
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text("不使用 AI 总结 (仅抓取标题与原文)"),
                          ),
                          ..._availableModels.map((m) {
                            return DropdownMenuItem<String>(
                              value: m['id'],
                              child: Text(m['custom_name'] ?? ''),
                            );
                          }),
                        ],
                        onChanged: (val) {
                          setModalState(() {
                            selectedModelId = val;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("每日定时自动任务", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              Text("启用后后台将每日定时读取", style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                          Switch(
                            value: enableSchedule,
                            onChanged: (val) {
                              setModalState(() {
                                enableSchedule = val;
                              });
                            },
                          ),
                        ],
                      ),
                      if (enableSchedule) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.access_time, size: 18, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text("设定读取时间: $scheduleTime", style: const TextStyle(fontWeight: FontWeight.w600)),
                            const Spacer(),
                            OutlinedButton(
                              onPressed: () async {
                                final parts = scheduleTime.split(':');
                                int initialHour = 9;
                                int initialMinute = 0;
                                if (parts.length == 2) {
                                  initialHour = int.tryParse(parts[0]) ?? 9;
                                  initialMinute = int.tryParse(parts[1]) ?? 0;
                                }
                                final pickedTime = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
                                  builder: (context, child) {
                                    return Theme(
                                      data: Theme.of(context).copyWith(
                                        colorScheme: ColorScheme.dark(
                                          primary: Theme.of(context).colorScheme.primary,
                                          onPrimary: Theme.of(context).colorScheme.onPrimary,
                                          surface: Theme.of(context).colorScheme.surface,
                                          onSurface: Theme.of(context).colorScheme.onSurface,
                                        ),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (pickedTime != null) {
                                  final hr = pickedTime.hour.toString().padLeft(2, '0');
                                  final min = pickedTime.minute.toString().padLeft(2, '0');
                                  setModalState(() {
                                    scheduleTime = "$hr:$min";
                                  });
                                }
                              },
                              child: const Text("选择时间"),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("取消"),
                ),
                FilledButton(
                  onPressed: () async {
                    final data = {
                      "name": nameController.text.trim(),
                      "url": urlController.text.trim(),
                      "schedule_time": enableSchedule ? scheduleTime : "",
                      "model_id": selectedModelId ?? "",
                    };

                    if (isEdit) {
                      await ApiService.updateRssFeed(feed['id'], data);
                    } else {
                      await ApiService.createRssFeed(data);
                    }
                    if (mounted) {
                      Navigator.pop(context);
                      _loadFeeds();
                      _loadArticles();
                    }
                  },
                  child: const Text("保存"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteFeed(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("确认删除"),
        content: Text("确定要删除订阅源 '$name' 吗？这会同步清除该源下的所有 AI 新闻文章。"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("取消"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text("确定删除"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ApiService.deleteRssFeed(id);
      _loadFeeds();
      _loadArticles();
    }
  }

  Future<void> _deleteArticle(String id) async {
    final success = await ApiService.deleteRssArticle(id);
    if (success) {
      setState(() {
        _articles.removeWhere((a) => a['id'] == id);
      });
    }
  }

  Future<void> _clearAllArticles() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("确认清空"),
        content: const Text("您确定要彻底清空数据库中所有已总结的新闻文章吗？此操作无法撤销。"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("取消"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text("确认清空"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await ApiService.clearAllRssArticles();
      if (success) {
        setState(() {
          _articles.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("已成功清空所有新闻文章")),
        );
      }
    }
  }

  Future<void> _openArticleUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri);
    }
  }

  void _readArticleContent(Map<String, dynamic> art) {
    Navigator.pushNamed(context, '/rss-article-detail', arguments: art);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Header Row: Title on Left, TabBar on Right
        isMobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "AI 网页阅读与新闻总结",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TabBar(
                    controller: _tabController,
                    labelColor: theme.colorScheme.primary,
                    unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
                    indicatorColor: theme.colorScheme.primary,
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(icon: Icon(Icons.article_outlined), text: "AI 新闻阅读"),
                      Tab(icon: Icon(Icons.settings_outlined), text: "订阅源管理"),
                    ],
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "AI 新网页阅读与新闻总结",
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(
                    width: 320,
                    child: TabBar(
                      controller: _tabController,
                      labelColor: theme.colorScheme.primary,
                      unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
                      indicatorColor: theme.colorScheme.primary,
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(icon: Icon(Icons.article_outlined), text: "AI 新闻阅读"),
                        Tab(icon: Icon(Icons.settings_outlined), text: "订阅源管理"),
                      ],
                    ),
                  ),
                ],
              ),
        const SizedBox(height: 20),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildArticlesTab(isMobile, theme, isDark),
              _buildFeedsTab(isMobile, theme, isDark),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildArticlesTab(bool isMobile, ThemeData theme, bool isDark) {
    if (_isLoadingArticles) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter Row
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text("全部源"),
                        selected: _selectedFeedFilter == null,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedFeedFilter = null;
                            });
                            _loadArticles();
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      ..._feeds.map((feed) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(feed['name'] ?? ''),
                            selected: _selectedFeedFilter == feed['id'],
                            onSelected: (selected) {
                              setState(() {
                                _selectedFeedFilter = selected ? feed['id'] : null;
                              });
                              _loadArticles();
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              if (_articles.isNotEmpty) ...[
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: _clearAllArticles,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: Colors.redAccent),
                  label: const Text("清空新闻", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ],
          ),
        ),
        
        // Articles List
        Expanded(
          child: _articles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.feed_outlined, size: 48, color: theme.colorScheme.onSurface.withOpacity(0.3)),
                      const SizedBox(height: 16),
                      Text(
                        "暂无已总结的新闻，请先前往“订阅源管理”点击立即读取",
                        style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 600,
                    mainAxisExtent: isMobile ? 220 : 250,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _articles.length,
                  itemBuilder: (context, index) => _buildArticleCard(_articles[index], theme, isDark, isMobile),
                ),
        ),
      ],
    );
  }

  Widget _buildArticleCard(Map<String, dynamic> art, ThemeData theme, bool isDark, bool isMobile) {
    // Format pubTime
    String timeStr = "";
    if (art['published_at'] != null) {
      try {
        final parsed = DateTime.parse(art['published_at']);
        timeStr = "${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}";
      } catch (e) {
        timeStr = art['published_at'].toString();
      }
    }

    final hasAI = art['model_used'] != null && art['model_used'] != '';

    return Card(
      margin: isMobile ? const EdgeInsets.only(bottom: 16) : EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title & Source tag
            Row(
              children: [
                Expanded(
                  child: Text(
                    art['title'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.black12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    art['feed_name'] ?? 'RSS',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // AISummary / Summary content
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  art['ai_summary'] ?? art['summary'] ?? '暂无内容介绍',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: theme.colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Footer (Time, Model, Read Original, Delete)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Time & Model Used
                Row(
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.4)),
                    ),
                    if (hasAI) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "AI: ${art['model_used']}",
                          style: const TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                // Actions
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () => _readArticleContent(art),
                          icon: const Icon(Icons.menu_book, size: 14),
                          label: const Text("阅读正文", style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _openArticleUrl(art['url'] ?? ''),
                          icon: const Icon(Icons.launch, size: 14),
                          label: const Text("查看原文", style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                          onPressed: () => _deleteArticle(art['id']),
                          tooltip: "删除此文章",
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildFeedsTab(bool isMobile, ThemeData theme, bool isDark) {
    if (_isLoadingFeeds) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Action Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "抓取源列表 (${_feeds.length})",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            FilledButton.icon(
              onPressed: () => _showFeedDialog(),
              icon: const Icon(Icons.add),
              label: const Text("新增订阅源"),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _feeds.isEmpty
              ? Center(
                  child: Text(
                    "暂无抓取源",
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  ),
                )
              : ListView.builder(
                  itemCount: _feeds.length,
                  itemBuilder: (context, index) {
                    final feed = _feeds[index];
                    final String time = feed['schedule_time'] ?? '';
                    final hasSchedule = time.isNotEmpty;

                    final modelName = feed['model_name'] ?? '';
                    final hasModel = modelName != null && modelName != '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: isMobile
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    feed['name'] ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    feed['url'] ?? '',
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 12),
                                  _buildFeedStatusBadges(hasSchedule, time, hasModel, modelName),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: _buildFeedActionButtons(feed, theme),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          feed['name'] ?? '',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          feed['url'] ?? '',
                                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    flex: 2,
                                    child: _buildFeedStatusBadges(hasSchedule, time, hasModel, modelName),
                                  ),
                                  const SizedBox(width: 16),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: _buildFeedActionButtons(feed, theme),
                                  ),
                                ],
                              ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFeedStatusBadges(bool hasSchedule, String time, bool hasModel, String modelName) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: hasSchedule ? Colors.green.withOpacity(0.1) : Colors.amber.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasSchedule ? Icons.schedule : Icons.touch_app_outlined,
                size: 12,
                color: hasSchedule ? Colors.green : Colors.amber,
              ),
              const SizedBox(width: 4),
              Text(
                hasSchedule ? "定时: $time" : "仅手动触发",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: hasSchedule ? Colors.green : Colors.amber,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: hasModel ? Colors.blue.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.hub_outlined,
                size: 12,
                color: hasModel ? Colors.blue : Colors.grey,
              ),
              const SizedBox(width: 4),
              Text(
                hasModel ? "总结模型: $modelName" : "无总结模型",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: hasModel ? Colors.blue : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildFeedActionButtons(Map<String, dynamic> feed, ThemeData theme) {
    return [
      IconButton(
        icon: const Icon(Icons.refresh, color: Colors.blueAccent),
        onPressed: () => _triggerImmediateScrape(feed),
        tooltip: "立即读取并总结",
      ),
      IconButton(
        icon: const Icon(Icons.edit_outlined),
        onPressed: () => _showFeedDialog(feed),
        tooltip: "编辑配置",
      ),
      IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
        onPressed: () => _deleteFeed(feed['id'], feed['name'] ?? ''),
        tooltip: "删除",
      ),
    ];
  }
}

class ScrapeProgressDialog extends StatefulWidget {
  final String feedId;
  final String feedName;
  final String? modelId;

  const ScrapeProgressDialog({
    super.key,
    required this.feedId,
    required this.feedName,
    this.modelId,
  });

  @override
  State<ScrapeProgressDialog> createState() => _ScrapeProgressDialogState();
}

class _ScrapeProgressDialogState extends State<ScrapeProgressDialog> {
  int _elapsedSeconds = 0;
  late DateTime _startTime;
  bool _isFinished = false;
  bool _success = false;
  String _statusMessage = "正在启动抓取任务并建立连接...";
  List<bool> _stepsCompleted = [false, false, false, false];
  List<bool> _stepsActive = [true, false, false, false];

  String _currentArticleTitle = "";
  String _streamingSummary = "";

  
  StreamSubscription<String>? _subscription;
  final ScrollController _scrollController = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _startTimer();
    _connectToScrapeStream();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _isFinished) {
        timer.cancel();
        return;
      }
      setState(() {
        _elapsedSeconds = DateTime.now().difference(_startTime).inSeconds;
      });
    });
  }

  void _connectToScrapeStream() {
    _subscription = ApiService.triggerScrapeStream(widget.feedId, modelId: widget.modelId).listen(
      (line) {
        if (!mounted) return;
        if (line.startsWith("data: ")) {
          final data = line.substring(6).trim();
          if (data == "connected") {
            setState(() {
              _statusMessage = "已连接至后端，开始解析 RSS 数据...";
            });
            return;
          }
          try {
            final parsed = jsonDecode(data);
            if (parsed is Map<String, dynamic>) {
              final type = parsed['type'];
              if (type == 'status') {
                setState(() {
                  _statusMessage = parsed['message'] ?? '';
                  if (_statusMessage.contains("拉取") || _statusMessage.contains("XML")) {
                    _stepsCompleted = [false, false, false, false];
                    _stepsActive = [true, false, false, false];
                  } else if (_statusMessage.contains("排重") || _statusMessage.contains("对比")) {
                    _stepsCompleted = [true, false, false, false];
                    _stepsActive = [false, true, false, false];
                  } else if (_statusMessage.contains("正文") || _statusMessage.contains("总结")) {
                    _stepsCompleted = [true, true, false, false];
                    _stepsActive = [false, false, true, false];
                  }
                });
              } else if (type == 'article_start') {
                setState(() {
                  _currentArticleTitle = parsed['title'] ?? '';
                  _streamingSummary = "";
                  _stepsCompleted = [true, true, false, false];
                  _stepsActive = [false, false, true, false];
                  _statusMessage = "正在解析并总结: $_currentArticleTitle";
                });
              } else if (type == 'ai_chunk') {
                setState(() {
                  _streamingSummary += parsed['chunk'] ?? '';
                });
                _scrollToBottom();
              } else if (type == 'article_end') {
                setState(() {
                  _stepsCompleted = [true, true, true, false];
                  _stepsActive = [false, false, false, true];
                });
              } else if (type == 'done') {
                final newCount = parsed['new_count'] ?? 0;
                setState(() {
                  _isFinished = true;
                  _success = true;
                  _stepsCompleted = [true, true, true, true];
                  _stepsActive = [false, false, false, false];
                  _statusMessage = "抓取与 AI 总结成功！新增 $newCount 篇文章。";
                });
                _closeDelayed(true);
              } else if (type == 'error') {
                final errMsg = parsed['error'] ?? '';
                setState(() {
                  _isFinished = true;
                  _success = false;
                  _statusMessage = "抓取失败: $errMsg";
                });
                _closeDelayed(false);
              }
            }
          } catch (e) {
            // ignore
          }
        }
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _isFinished = true;
          _success = false;
          _statusMessage = "读取连接异常: $err";
        });
        _closeDelayed(false);
      },
      onDone: () {
        if (!mounted) return;
        if (!_isFinished) {
          setState(() {
            _isFinished = true;
            _success = true;
            _statusMessage = "抓取任务运行结束";
          });
          _closeDelayed(true);
        }
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _closeDelayed(bool result) async {
    await Future.delayed(const Duration(milliseconds: 2000));
    if (mounted) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.sync, color: Colors.blueAccent),
          const SizedBox(width: 8),
          Expanded(child: Text("抓取: ${widget.feedName}")),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: _isFinished ? 1.0 : null,
              color: _isFinished && !_success ? Colors.redAccent : Colors.blueAccent,
            ),
            const SizedBox(height: 20),
            Text(
              _statusMessage,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              "已耗时: $_elapsedSeconds 秒",
              style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 12),
            ),
            
            if (_streamingSummary.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text("AI 总结流式输出中:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
              const SizedBox(height: 6),
              Container(
                height: 120,
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                ),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Text(
                        _streamingSummary,
                        style: const TextStyle(fontSize: 13, height: 1.5, fontFamily: 'Roboto'),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            _buildStepRow(0, "正在连接并拉取 RSS 源 XML 数据"),
            _buildStepRow(1, "解析 XML 并对比过滤重复新闻"),
            _buildStepRow(2, "抓取网页正文并生成 AI 总结"),
            _buildStepRow(3, "持久化存储到后端数据库"),
          ],
        ),
      ),
      actions: [
        if (!_isFinished)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context, null);
            },
            icon: const Icon(Icons.dns, size: 16),
            label: const Text("后台运行"),
          ),
        if (_isFinished)
          TextButton(
            onPressed: () => Navigator.pop(context, _success),
            child: const Text("关闭"),
          )
      ],
    );
  }

  Widget _buildStepRow(int index, String description) {
    IconData icon = Icons.radio_button_unchecked;
    Color color = Colors.grey;
    if (_stepsCompleted[index]) {
      icon = Icons.check_circle;
      color = Colors.green;
    } else if (_stepsActive[index]) {
      icon = Icons.sync;
      color = Colors.blueAccent;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                fontSize: 13,
                color: _stepsCompleted[index]
                    ? Colors.green
                    : _stepsActive[index]
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                fontWeight: _stepsActive[index] ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RssArticleDetailPage extends StatefulWidget {
  const RssArticleDetailPage({super.key});

  @override
  State<RssArticleDetailPage> createState() => _RssArticleDetailPageState();
}

class _RssArticleDetailPageState extends State<RssArticleDetailPage> {
  int _activeViewIndex = 0;
  Map<String, dynamic>? _art;
  String? _viewId;
  bool _isViewRegistered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isViewRegistered) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        _art = Map<String, dynamic>.from(args);
        _viewId = 'iframe_proxy_${_art!['id']}';
        
        final proxyUrl = "${ApiService.baseUrl}/api/admin/rss/proxy-url?url=${Uri.encodeComponent(_art!['url'] ?? '')}&token=${ApiService.token}";
        
        ui_web.platformViewRegistry.registerViewFactory(
          _viewId!,
          (int viewId) {
            final iframe = web.document.createElement('iframe') as web.HTMLIFrameElement;
            iframe.src = proxyUrl;
            iframe.style.border = 'none';
            iframe.style.width = '100%';
            iframe.style.height = '100%';
            return iframe;
          },
        );
        _isViewRegistered = true;
      }
    }
  }

  Widget _buildTabButton(int index, String label) {
    final theme = Theme.of(context);
    final isActive = _activeViewIndex == index;
    return OutlinedButton(
      onPressed: () {
        setState(() {
          _activeViewIndex = index;
        });
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: isActive ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
        backgroundColor: isActive ? theme.colorScheme.primary : Colors.transparent,
        side: BorderSide(color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.2)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_art == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    String timeStr = "";
    if (_art!['published_at'] != null) {
      try {
        final parsed = DateTime.parse(_art!['published_at']);
        timeStr = "${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}";
      } catch (e) {
        timeStr = _art!['published_at'].toString();
      }
    }

    final hasAI = _art!['model_used'] != null && _art!['model_used'] != '';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_art!['feed_name'] ?? '新闻详情', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.launch),
            onPressed: () async {
              final uri = Uri.tryParse(_art!['url'] ?? '');
              if (uri != null) {
                await launchUrl(uri);
              }
            },
            tooltip: "浏览器打开原文",
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Centered Tab Buttons
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: theme.colorScheme.surface,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildTabButton(0, "智能总结与正文"),
                  const SizedBox(width: 16),
                  _buildTabButton(1, "中转网页原文"),
                ],
              ),
            ),
            const Divider(height: 1),
            // View Switcher
            Expanded(
              child: _activeViewIndex == 0
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 800),
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                        child: ListView(
                          children: [
                            Text(
                              _art!['title'] ?? '',
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, height: 1.3),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Text(
                                  timeStr,
                                  style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 13),
                                ),
                                const SizedBox(width: 12),
                                if (hasAI)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      "AI: ${_art!['model_used']}",
                                      style: const TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            if (_art!['ai_summary'] != null && _art!['ai_summary'] != '') ...[
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.blue.withOpacity(0.08) : Colors.blue.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.auto_awesome, color: Colors.blue, size: 18),
                                        const SizedBox(width: 8),
                                        Text(
                                          "AI 总结说明",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.blue[200] : Colors.blue[800],
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _art!['ai_summary'],
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.6,
                                        color: theme.colorScheme.onSurface.withOpacity(0.9),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                            const Text(
                              "网页正文内容",
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            const Divider(),
                            const SizedBox(height: 12),
                            Text(
                              _art!['content'] != null && _art!['content'] != '' 
                                  ? _art!['content'] 
                                  : (_art!['summary'] != null && _art!['summary'] != '' ? _art!['summary'] : '暂无内容介绍'),
                              style: const TextStyle(fontSize: 15, height: 1.7),
                            ),
                          ],
                        ),
                      ),
                    )
                  : HtmlElementView(viewType: _viewId!),
            ),
          ],
        ),
      ),
    );
  }
}
