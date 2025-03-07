import 'package:color_logger/color_logger.dart';

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
  aar('aar');

  const BuildType(this.value);

  final String value;
}

enum BuildLibrary {
  flutter('flutter'),
  unity('unity');

  const BuildLibrary(this.value);

  final String value;
}
