import 'package:flutter/material.dart';

import '../core/theme/theme_controller.dart';
import '../models/myschool/myschool_homework.dart';
import '../services/myschool/myschool_service.dart';
import '../services/myschool/myschool_tokens.dart';

class MySchoolHomeScreen extends StatefulWidget {
  final MySchoolTokens tokens;
  final ThemeController themeController;
  const MySchoolHomeScreen({
    super.key,
    required this.tokens,
    required this.themeController,
  });

  @override
  State<MySchoolHomeScreen> createState() => _MySchoolHomeScreenState();
}

class _MySchoolHomeScreenState extends State<MySchoolHomeScreen> {
  final _service = MySchoolService();
  List<MySchoolHomework>? _homeworks;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.fetchHomeworks(widget.tokens, weeks: 4);
      if (!mounted) return;
      setState(() {
        _homeworks = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Моя школа — ДЗ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    final list = _homeworks ?? const <MySchoolHomework>[];
    if (list.isEmpty) {
      return const Center(child: Text('Нет ДЗ за последние 4 недели'));
    }

    // Группируем по дате (issue_date).
    final byDate = <DateTime, List<MySchoolHomework>>{};
    for (final h in list) {
      final d = h.date;
      if (d == null) continue;
      final key = DateTime(d.year, d.month, d.day);
      byDate.putIfAbsent(key, () => []).add(h);
    }
    final days = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: days.length,
        itemBuilder: (_, i) {
          final day = days[i];
          final items = byDate[day]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (i > 0) const SizedBox(height: 20),
              Text(
                _dayLabel(day),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              for (final h in items)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (h.subjectName != null)
                          Text(
                            h.subjectName!,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        const SizedBox(height: 4),
                        Text('ДЗ: ${h.description}'),
                        if (h.planReadyDate != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Сделать до ${_fmt(h.planReadyDate!)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (h.materials.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          for (final m in h.materials)
                            Text(
                              '📎 ${m.name}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _dayLabel(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  static String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }
}