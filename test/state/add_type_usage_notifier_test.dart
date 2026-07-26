import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_system/state/add_type_usage_notifier.dart';

void main() {
  test('starts empty', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(addTypeUsageProvider), isEmpty);
  });

  test('recordAdd increments the count for a primaryType', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(addTypeUsageProvider.notifier);
    notifier.recordAdd('art');
    notifier.recordAdd('art');
    notifier.recordAdd('activity');

    expect(container.read(addTypeUsageProvider), {'art': 2, 'activity': 1});
  });
}
