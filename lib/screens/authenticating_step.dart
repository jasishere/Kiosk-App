import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shown while a note sits in escrow under the UV camera.
///
/// Deliberately short on detail: the customer cannot act here, the wait is a
/// second or two, and narrating the classifier's internals ("running YOLOv8
/// inference") only invites the question of what happens when it is wrong.
class AuthenticatingStep extends StatelessWidget {
  const AuthenticatingStep({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 52,
            height: 52,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              color: AppColors.green,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Text('Checking your note', style: AppText.title),
          const SizedBox(height: AppSpace.xs),
          Text('This takes a moment. Please hold on.', style: AppText.body),
        ],
      ),
    );
  }
}
