import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  test('demo credentials are 1234', () {
    expect(DemoCredentials.password, '1234');
    expect(DemoCredentials.pairCode, '1234');
  });
}
