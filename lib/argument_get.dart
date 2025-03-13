import 'package:args/args.dart';
import 'package:prompts/prompts.dart' as prompts;

class ArgumentGet {
  final ArgResults? argResults;
  ArgumentGet(this.argResults);

  String getString(
    String name, {
    List<String> allowed = const [],
    bool Function(String)? validate,
  }) {
    String? value = argResults?[name];
    if (value == null) {
      if (allowed.isNotEmpty) {
        value = prompts.choose(
          '请选择$name:',
          allowed,
        );
      }
      value ??= prompts.get('请输入$name:', validate: validate);
    }
    return value;
  }

  bool getBool(String name) {
    bool? value = argResults?[name];
    value ??= prompts.getBool('请输入$name:');
    return value;
  }

  int getInt(String name, {int? defaultValue}) {
    String? value = argResults?[name];
    value ??= '${prompts.getInt('请输入$name:', defaultsTo: defaultValue)}';
    return int.parse(value);
  }
}
