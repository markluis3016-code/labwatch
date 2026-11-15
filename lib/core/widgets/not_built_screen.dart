import 'package:flutter/material.dart';

/// Honest marker for modules that are not implemented yet. Remove each use
/// as the real module lands. See README "Feature status".
class NotBuiltScreen extends StatelessWidget {
  const NotBuiltScreen(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.construction_rounded, size: 48),
                const SizedBox(height: 12),
                Text('$title is not implemented yet',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text('This module is scheduled in a later build step.',
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
}
