import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'JoinController.dart';
import 'examples_menu_screen.dart';


/// Room-name entry point: create a room as host (publishes mic/camera
/// immediately) or join an existing one as a guest (subscribe-only).
class JoinScreen extends GetView<JoinController> {
  const JoinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Get.put(JoinController());

    return Scaffold(
      appBar: AppBar(title: const Text('VideoHub Group Chat')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.groups_rounded, size: 64),
                const SizedBox(height: 16),
                Text('Group Video Chat', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Create a room to host, or join one someone else already started.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: controller.roomCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Room name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Join as host, publishing:', style: Theme.of(context).textTheme.labelLarge),
                ),
                const SizedBox(height: 8),
                Obx(
                  () => RadioGroup<HostJoinMode>(
                    groupValue: controller.joinMode.value,
                    onChanged: (value) => controller.joinMode.value = value!,
                    child: Column(
                      children: HostJoinMode.values
                          .map(
                            (mode) => RadioListTile<HostJoinMode>(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(mode.label),
                              value: mode,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Obx(() {
                  final error = controller.error.value;
                  if (error == null) return const SizedBox.shrink();
                  return Column(
                    children: [
                      Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 12),
                    ],
                  );
                }),
                Obx(
                  () => FilledButton.icon(
                    onPressed: controller.busy.value
                        ? null
                        : () => controller.join(context, asHost: true),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Create & join as host'),
                  ),
                ),
                const SizedBox(height: 12),
                Obx(
                  () => OutlinedButton.icon(
                    onPressed: controller.busy.value
                        ? null
                        : () => controller.join(context, asHost: false),
                    icon: const Icon(Icons.login),
                    label: const Text('Join as guest'),
                  ),
                ),
                Obx(() {
                  if (!controller.busy.value) return const SizedBox.shrink();
                  return const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: CircularProgressIndicator(),
                  );
                }),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(builder: (_) => const ExamplesMenuScreen()),
                  ),
                  icon: const Icon(Icons.apps),
                  label: const Text('Browse feature examples'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
