import 'package:flutter/material.dart';

/// Список образовательных учреждений с маркерами.
class SchoolsTile extends StatelessWidget {
  final List<String> schools;

  const SchoolsTile({super.key, required this.schools});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Образовательные учреждения',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (schools.isEmpty)
          Text('—', style: theme.textTheme.titleMedium)
        else
          ...schools.map(
                (name) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Expanded(
                    child: Text(name, style: theme.textTheme.titleMedium),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}