import 'package:flutter_test/flutter_test.dart';
import 'package:kofu_reader/data/updater.dart';

void main() {
  test('compara versiones numéricamente', () {
    expect(Updater.isNewer('1.1.0', '1.0.0'), isTrue);
    expect(Updater.isNewer('1.2.10', '1.2.9'), isTrue);
    expect(Updater.isNewer('2.0.0', '1.9.9'), isTrue);
    expect(Updater.isNewer('1.0.0', '1.0.0'), isFalse);
    expect(Updater.isNewer('1.0.0', '1.0.1'), isFalse);
    expect(Updater.isNewer('1.1', '1.0.5'), isTrue);
    expect(Updater.isNewer('1.1.0+7', '1.1.0'), isFalse);
  });
}
