import 'package:args/args.dart';
import 'package:prompts/prompts.dart' as prompts;

class ArgumentGet {
  final ArgResults? argResults;
  ArgumentGet(this.argResults);

  String getString(
    String name,
    String description, {
    String? defaultValue,
    Iterable<String> allowed = const [],
    bool Function(String)? validate,
  }) {
    String? value = argResults?[name];
    if (value == null) {
      if (allowed.isNotEmpty) {
        value = prompts.choose(
          description,
          allowed.toSet(),
          defaultsTo: defaultValue,
        );
      }
      value ??= prompts.get(
        description,
        validate: validate,
        defaultsTo: defaultValue,
      );
    }
    return value;
  }

  bool getBool(
    String name,
    String description, {
    bool defaultValue = false,
  }) {
    bool? value = argResults?[name];
    value ??= prompts.getBool(description, defaultsTo: defaultValue);
    return value;
  }

  int getInt(String name, String description, {int? defaultValue}) {
    String? value = argResults?[name];
    value ??= '${prompts.getInt(description, defaultsTo: defaultValue)}';
    return int.parse(value);
  }
}
