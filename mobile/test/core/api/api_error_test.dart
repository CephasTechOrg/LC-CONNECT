import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/api/api_error.dart';

DioException _rejected(Object detail) {
  final options = RequestOptions(path: '/scholars/me');
  return DioException(
    requestOptions: options,
    response: Response(requestOptions: options, statusCode: 422, data: {'detail': detail}),
  );
}

void main() {
  test('a string detail is shown as written', () {
    expect(apiErrorMessage(_rejected('Too many requests'), fallback: 'x'), 'Too many requests');
  });

  test('a 422 list names the field instead of falling back to "Something went wrong"', () {
    final error = _rejected([
      {
        'loc': ['body', 'linkedin_url'],
        'msg': 'Value error, URL must start with http:// or https://',
        'type': 'value_error',
      },
    ]);
    expect(
      apiErrorMessage(error, fallback: 'Something went wrong.'),
      'LinkedIn URL: URL must start with http:// or https://',
    );
  });

  test('a nested field is humanized from its key', () {
    expect(
      validationMessage([
        {
          'loc': ['body', 'projects', 0, 'start_date'],
          'msg': 'Invalid date',
        },
      ]),
      'Start date: Invalid date',
    );
  });

  test('an unexpected detail shape falls back', () {
    expect(apiErrorMessage(_rejected(42), fallback: 'fallback'), 'fallback');
    expect(validationMessage(const []), isNull);
  });
}
