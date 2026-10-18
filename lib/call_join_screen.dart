import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'CallJoinController.dart';

/// 1:1 call entry point: start a call as the caller (rings [calleeIdCtrl]),
/// or join one already started by entering its call id as the callee.
class CallJoinScreen extends StatelessWidget {
  const CallJoinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(CallJoinController());

    return Scaffold(
      appBar: AppBar(title: const Text('1:1 Call Demo')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.call, size: 64),
                const SizedBox(height: 16),
                Text(
                  'Peer-to-Peer Call',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Start a call to ring someone, or join one with its call id.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                Text('Start a call', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: controller.callerIdCtrl,
                  decoration: const InputDecoration(labelText: 'Caller id', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller.calleeIdCtrl,
                  decoration: const InputDecoration(labelText: 'Callee id', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Obx(
                  () => FilledButton.icon(
                    onPressed: controller.busy.value ? null : () => controller.startCall(context),
                    icon: const Icon(Icons.call_made),
                    label: const Text('Start call'),
                  ),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                Text('Join a call', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: controller.callIdCtrl,
                  decoration: const InputDecoration(labelText: 'Call id', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Obx(
                  () => OutlinedButton.icon(
                    onPressed: controller.busy.value ? null : () => controller.joinCall(context),
                    icon: const Icon(Icons.call_received),
                    label: const Text('Join call'),
                  ),
                ),
                Obx(() {
                  final error = controller.error.value;
                  if (error == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  );
                }),
                Obx(() {
                  if (!controller.busy.value) return const SizedBox.shrink();
                  return const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
