import 'package:color_logger/color_logger.dart';
import 'package:meta_tool/app_home_dir.dart';

final logger = ColorLogger();

enum BuildConfiguration {
  debug('debug'),
  release('release');

  const BuildConfiguration(this.value);
  final String value;
}

enum BuildPlatform {
  ios('ios'),
  android('android');

  const BuildPlatform(this.value);
  final String value;
}

enum BuildType {
  framework('framework'),
  aar('aar'),
  library('library');

  const BuildType(this.value);
  final String value;
}

enum BuildLibrary {
  flutter('flutter'),
  unity('unity');

  const BuildLibrary(this.value);
  final String value;
}

enum BuildPublish {
  test('test'),
  store('store');

  const BuildPublish(this.value);
  final String value;
}

late AppHomeDir appHomeDir;
