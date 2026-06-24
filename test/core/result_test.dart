import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/core/result.dart';

void main() {
  test('Ok carries a value', () {
    const Result<int> r = Ok(42);
    expect(r.isOk, isTrue);
    expect(r.valueOrNull, 42);
    expect(r.failureOrNull, isNull);
  });

  test('Err carries a typed failure', () {
    const Result<int> r = Err(WrongPassphraseFailure());
    expect(r.isOk, isFalse);
    expect(r.valueOrNull, isNull);
    expect(r.failureOrNull, isA<WrongPassphraseFailure>());
    expect(r.failureOrNull!.message, isNotEmpty);
  });
}
