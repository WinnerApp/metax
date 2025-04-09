import 'dart:io';

import 'package:meta_tool/argument_get.dart';
import 'package:meta_tool/cache/framework_aar_cache.dart';
import 'package:meta_tool/commands/build/build_cache_command.dart';
import 'package:meta_tool/common.dart';
import 'package:meta_tool/define.dart';
import 'package:path/path.dart';
import 'package:process_runner/process_runner.dart';

class FlutterAarCommand extends BuildCacheCommand {
  @override
  String get description => '打包flutter aar';

  @override
  String get name => 'flutter';

  FlutterAarCommand() {
    argParser.addOption(
      'configuration',
      abbr: 'c',
      help: 'flutter工程配置，debug/release',
      allowed: BuildConfiguration.values.map((e) => e.name).toList(),
    );
    argParser.addOption(
      'branch',
      help: '分支名称,指定分支则进行切换到对应分支',
    );
  }

  late String configuration;
  @override
  Future<void> run() async {
    await super.run();
    if (useMock) {
      await copyDirToDir(
        MockType.flutterAar.mockDir(appHomeDir),
        MockType.flutterAar.sourceCacheDir(appHomeDir),
      );
      loggerSuccess('打包Flutter AAR完成!');
      return;
    }
    configuration = ArgumentGet(argResults).getString(
      'configuration',
      '请选择Flutter AAR构建配置',
      allowed: BuildConfiguration.values.map((e) => e.name).toList(),
    );
    final workspaceDir = appHomeDir.flutterDir;
    final pubspecFile = File(join(workspaceDir.path, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw Exception('${workspaceDir.path} 不是一个Flutter工程');
    }
    final argBranch = argResults?['branch'];
    if (argBranch != null) {
      await switchBranch(workspaceDir.path, argBranch);
    }
    final branch = await getCurrentBranch(workspaceDir.path);
    final commitHash = await getCurrentCommitHash(workspaceDir.path);
    final commitTime = await getCommitTime(workspaceDir.path, commitHash);
    BuildConfiguration buildConfiguration;
    buildConfiguration = BuildConfiguration.values.firstWhere(
      (e) => e.name == configuration,
    );
    final flutterCache = AarCache(
      branch: branch,
      buildConfiguration: buildConfiguration,
      buildLibrary: BuildLibrary.flutter,
      buildId: 0,
    );
    final buildCacheDir = join(workspaceDir.path, 'build', 'host');
    await updateCache(
      cache: flutterCache,
      commitHash: commitHash,
      buildCacheDir: buildCacheDir,
      commitTime: commitTime,
      cacheId: commitHash,
      forceUpdate: !isUseCache,
    );
    loggerSuccess('导出Flutter AAR完成!');
    if (isUpload) {
      loggerDebug('上传缓存...');
      await uploadCacheResource(
        buildPlatform: BuildPlatform.android,
        buildLibrary: BuildLibrary.flutter,
        buildConfiguration: buildConfiguration,
        buildType: BuildType.aar,
        branch: branch,
        commitHash: commitHash,
        commitTime: commitTime,
        buildId: 0,
      );
    }
  }

  @override
  Future<void> buildCache() async {
    await speedUpFlutterAarBuild();
    // flutter pub get
    await ProcessRunner().runProcess(
      ['flutter', 'pub', 'get'],
      workingDirectory: appHomeDir.flutterDir,
      printOutput: true,
    );
    // metaapp_flutter/buildConfigs/android
    final androidConfigDir =
        Directory(join(appHomeDir.flutterDir.path, 'buildConfigs', 'android'));
    if (!androidConfigDir.existsSync()) {
      throw Exception('buildConfigs/android目录不存在: ${androidConfigDir.path}');
    }

    final toConfigDir = Directory(join(appHomeDir.flutterDir.path, '.android'));
    if (!toConfigDir.existsSync()) {
      throw Exception('.android目录不存在: ${toConfigDir.path}');
    }

    if (await androidConfigDir.exists()) {
      /// cp -r -f "$android_config_dir"/* "$generate_android_dir"
      await ProcessRunner().runProcess(
        ['cp', '-rf', "${androidConfigDir.path}/.", toConfigDir.path],
        workingDirectory: appHomeDir.flutterDir,
        printOutput: true,
      );
    }

    if (configuration == 'debug') {
      /// flutter build aar --no-profile --no-release --verbose
      await ProcessRunner().runProcess(
        [
          'flutter',
          'build',
          'aar',
          '--no-profile',
          '--no-release',
          '--target-platform=android-arm64',
          '--verbose',
        ],
        workingDirectory: appHomeDir.flutterDir,
        printOutput: true,
      );
    } else {
      /// flutter build aar --no-debug --no-profile --verbose
      await ProcessRunner().runProcess(
        [
          'flutter',
          'build',
          'aar',
          '--no-debug',
          '--no-profile',
          '--target-platform=android-arm64',
          '--verbose',
        ],
        workingDirectory: appHomeDir.flutterDir,
        printOutput: true,
      );
    }
  }

  /// 提升Flutter aar编译速度
  Future<void> speedUpFlutterAarBuild() async {
    final flutterCommandDir = await getFlutterCommandDir(appHomeDir);
    final buildAarScriptFile = File(join(
      flutterCommandDir,
      'packages',
      'flutter_tools',
      'gradle',
      'aar_init_script.gradle',
    ));
    if (!buildAarScriptFile.existsSync()) {
      throw Exception(
          'aar_init_script.gradle文件不存在: ${buildAarScriptFile.path}');
    }
    await buildAarScriptFile.writeAsString(r'''
// This script is used to initialize the build in a module or plugin project.
// During this phase, the script applies the Maven plugin and configures the
// destination of the local repository.
// The local repository will contain the AAR and POM files.

import java.nio.file.Paths
import org.gradle.api.Project
import org.gradle.api.artifacts.Configuration
import org.gradle.api.publish.maven.MavenPublication

void configureProject(Project project, String outputDir) {
    if (!project.hasProperty("android")) {
        throw new GradleException("Android property not found.")
    }
    if (!project.android.hasProperty("libraryVariants")) {
        throw new GradleException("Can't generate AAR on a non Android library project.");
    }

    // Snapshot versions include the timestamp in the artifact name.
    // Therefore, remove the snapshot part, so new runs of `flutter build aar` overrides existing artifacts.
    // This version isn't relevant in Flutter since the pub version is used
    // to resolve dependencies.
    project.version = project.version.replace("-SNAPSHOT", "")

    if (project.hasProperty("buildNumber")) {
        project.version = project.property("buildNumber")
    }

    project.components.forEach { component ->
        if (component.name != "all") {
            addAarTask(project, component)
        }
    }

    project.publishing {
        repositories {
            maven {
                url = uri("file://$outputDir/outputs/repo")
            }
        }
    }

    if (!project.property("is-plugin").toBoolean()) {
        return
    }

    String storageUrl = System.getenv('FLUTTER_STORAGE_BASE_URL') ?: "https://storage.googleapis.com"

    String engineRealm = Paths.get(getFlutterRoot(project), "bin", "internal", "engine.realm")
        .toFile().text.trim()
    if (engineRealm) {
        engineRealm = engineRealm + "/"
    }

    // This is a Flutter plugin project. Plugin projects don't apply the Flutter Gradle plugin,
    // as a result, add the dependency on the embedding.
    project.repositories {
        maven {
            url "$storageUrl/${engineRealm}download.flutter.io"
        }
    }
    String engineVersion = Paths.get(getFlutterRoot(project), "bin", "internal", "engine.version")
        .toFile().text.trim()
    project.dependencies {
        // Add the embedding dependency.
        compileOnly ("io.flutter:flutter_embedding_release:1.0.0-$engineVersion") {
            // We only need to expose io.flutter.plugin.*
            // No need for the embedding transitive dependencies.
            transitive = false
        }
    }
}

void configurePlugin(Project project, String outputDir) {
    if (!project.hasProperty("android")) {
        // A plugin doesn't support the Android platform when this property isn't defined in the plugin.
        return
    }
    configureProject(project, outputDir)
}

String getFlutterRoot(Project project) {
    if (!project.hasProperty("flutter-root")) {
        throw new GradleException("The `-Pflutter-root` flag must be specified.")
    }
    return project.property("flutter-root")
}

void addAarTask(Project project, component) {
    String variantName = component.name.capitalize()
    String taskName = "assembleAar$variantName"
    project.tasks.create(name: taskName) {
        // This check is required to be able to configure the archives before `publish` runs.
        if (!project.gradle.startParameter.taskNames.contains(taskName)) {
            return
        }

        // Create a default MavenPublication for the variant (except "all" since that is used to publish artifacts in the new way)
        project.publishing.publications.create(component.name, MavenPublication) { pub ->
            groupId = "${pub.groupId}"
            artifactId = "${pub.artifactId}_${pub.name}"
            version = "${pub.version}"
            from component
        }

        // Generate the Maven artifacts.
        finalizedBy "publish"
    }
}

// maven-publish has to be applied _before_ the project gets evaluated, but some of the code in
// `configureProject` requires the project to be evaluated. Apply the maven plugin to all projects, but
// only configure it if it matches the conditions in `projectsEvaluated`

allprojects {
   apply plugin: "maven-publish"
}

// afterProject { project ->
//     // Exit early if either:
//     // 1. The project doesn't have the Android Gradle plugin applied.
//     // 2. The project has already defined which variants to publish (trying to re-define which
//     //    variants to publish will result in an error).
//     if (!project.hasProperty("android")) {
//         return
//     }
//     if (project.android.publishing.singleVariants.size() != 0) {
//         return
//     }

//     Closure addSingleVariants = {buildType ->
//         if (!project.android.productFlavors.isEmpty()) {
//             project.android.productFlavors.all{productFlavor ->
//                 project.android.publishing.singleVariant(
//                         productFlavor.name + buildType.name.capitalize()
//                 ) {
//                     withSourcesJar()
//                     withJavadocJar()
//                 }
//             }
//         } else {
//             project.android.publishing.singleVariant(buildType.name) {
//                 withSourcesJar()
//                 withJavadocJar()
//             }
//         }
//     }

//     project.android.buildTypes.all(addSingleVariants)
// }

projectsEvaluated {
    assert rootProject.hasProperty("is-plugin")
    if (rootProject.property("is-plugin").toBoolean()) {
        assert rootProject.hasProperty("output-dir")
        // In plugin projects, the root project is the plugin.
        configureProject(rootProject, rootProject.property("output-dir"))
        return
    }
    // The module project is the `:flutter` subproject.
    Project moduleProject = rootProject.subprojects.find { it.name == "flutter" }
    assert moduleProject != null
    assert moduleProject.hasProperty("output-dir")
    configureProject(moduleProject, moduleProject.property("output-dir"))

    // Gets the plugin subprojects.
    Set<Project> modulePlugins = rootProject.subprojects.findAll {
        it.name != "flutter" && it.name != "app"
    }
    // When a module is built as a Maven artifacts, plugins must also be built this way
    // because the module POM's file will include a dependency on the plugin Maven artifact.
    // This is due to the Android Gradle Plugin expecting all library subprojects to be published
    // as Maven artifacts.
    modulePlugins.each { pluginProject ->
        configurePlugin(pluginProject, moduleProject.property("output-dir"))
        moduleProject.android.libraryVariants.all { variant ->
            // Configure the `assembleAar<variantName>` task for each plugin's projects and make
            // the module's equivalent task depend on the plugin's task.
            String variantName = variant.name.capitalize()
            moduleProject.tasks.findByPath("assembleAar$variantName")
                .dependsOn(pluginProject.tasks.findByPath("assembleAar$variantName"))
        }
    }
}
''');
    loggerSuccess('提升Flutter aar编译加速设置完成!');
  }
}
