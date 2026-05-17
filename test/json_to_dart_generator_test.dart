import 'package:cotool/src/json_to_dart/json_to_dart_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generates nested Dart models from JSON', () {
    final code = JsonToDartGenerator().generate(
      rootClassName: 'UserModel',
      source: '''
{
  "id": 1,
  "user_name": "Song",
  "profile": {
    "avatar_url": "https://example.com/avatar.png"
  },
  "tags": ["Flutter"]
}
''',
    );

    expect(code, contains('class UserModel'));
    expect(code, contains('class Profile'));
    expect(code, contains('final String userName;'));
    expect(code, contains('Profile.fromJson'));
    expect(code, contains('List<String> tags'));
    expect(code, contains("'user_name': userName"));
  });
}
