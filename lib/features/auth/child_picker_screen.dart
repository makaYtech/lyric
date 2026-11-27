import 'package:flutter/material.dart';

import '../../domain/people/student_profile.dart';

class ChildOption {
  final int profileId;
  final StudentProfile profile;

  const ChildOption({required this.profileId, required this.profile});

  String get subtitle {
    final parts = <String>[
      if (profile.className != '—') profile.className,
      ...profile.schoolNames,
    ];
    return parts.isEmpty ? 'Ученик' : parts.join(' · ');
  }
}

/// Выбор ребёнка у родителя с несколькими детьми.
class ChildPickerScreen extends StatelessWidget {
  final List<ChildOption> children;
  final ValueChanged<ChildOption> onPicked;

  const ChildPickerScreen({
    super.key,
    required this.children,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Выберите ребёнка')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final child = children[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: cs.secondaryContainer,
                    foregroundColor: cs.onSecondaryContainer,
                    child: const Icon(Icons.person_outline),
                  ),
                  title: Text(child.profile.userName),
                  subtitle: Text(child.subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onPicked(child),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
