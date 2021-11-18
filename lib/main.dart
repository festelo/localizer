/*

dependencies:
  collection: ^1.14.13
  http: ^0.12.2

*/

import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;

void main(List<String> arguments) async {
  if (arguments.isEmpty) {
    print('First argument must be path to folder');
    return;
  }
  try {
    print('Trying to access files in ${arguments[0]}');
    final dir = Directory(arguments[0]);
    var files = (await dir.list().toList()).whereType<File>().toList();
    files = files.where((f) => f.path.split('.').last == 'json').toList();
    print('Json files found: ${files.length}');

    File getMainFile() {
      final tempFiles =
          files.asMap().map((a, e) => MapEntry(getFileName(e.path), e));

      if (arguments.length > 1) {
        final inp = arguments[1];
        final match = tempFiles.keys.firstWhere(
            (e) => e == inp || e == inp + '.json',
            orElse: () => null);
        if (match != null) {
          return tempFiles[match];
        }
        print('File $inp taken from arguments not found');
      }

      print('Whats your main file? (type `list` to show all)');
      while (true) {
        final inp = readLine().trim();
        if (inp == 'list') {
          print(tempFiles.keys.join('\n'));
          continue;
        }

        final match = tempFiles.keys.firstWhere(
            (e) => e == inp || e == inp + '.json',
            orElse: () => null);

        if (match == null) {
          print('File $inp not found');
          continue;
        }

        return tempFiles[match];
      }
    }

    final mainFile = getMainFile();
    print('File ${mainFile.path} picked as main');

    bool compare() {
      final mainContent = mainFile.readAsStringSync();
      final mainJson = Map<String, String>.from(jsonDecode(mainContent));
      final mainFileName = getFileName(mainFile.path);
      var ok = true;
      for (final file in files) {
        if (file == mainFile) continue;
        final currentFileName = getFileName(file.path);
        final currentContent = file.readAsStringSync();
        final currentJson =
            Map<String, String>.from(jsonDecode(currentContent));
        final equality = const DeepCollectionEquality.unordered();
        if (!equality.equals(
            currentJson.keys.toList(), mainJson.keys.toList())) {
          for (final cKey in currentJson.keys) {
            if (mainJson[cKey] == null) {
              print(
                  '$cKey is missing in $mainFileName, but found in $currentFileName');
              ok = false;
            }
          }
        }
      }
      return ok;
    }

    Future<void> syncKeys([String key]) async {
      final newLines = <String, List<String>>{};
      final mainContent = mainFile.readAsStringSync();
      final mainJson = Map<String, String>.from(jsonDecode(mainContent));
      final mainFileName = getFileName(mainFile.path);
      final mainLanguage = mainFileName.replaceAll('.json', '');
      for (final file in files) {
        if (file == mainFile) continue;
        final currentFileName = getFileName(file.path);
        final currentContent = file.readAsStringSync();
        final currentJson =
            Map<String, String>.from(jsonDecode(currentContent));
        final equality = const DeepCollectionEquality.unordered();
        if (!equality.equals(
            currentJson.keys.toList(), mainJson.keys.toList())) {
          for (final mKey in mainJson.keys) {
            if (key != null && mKey != key) continue;
            if (currentJson[mKey] == null) {
              if (newLines[mKey] == null) newLines[mKey] = [];
              newLines[mKey].add(currentFileName.replaceAll('.json', ''));
            }
          }
        }
      }
      print('New keys found: \n${newLines.keys.join('\n')}');
      final translated = <TranslationEntity>[];
      final total =
          newLines.values.map((e) => e.length).reduce((a, b) => a + b);
      for (final key in newLines.keys) {
        for (final language in newLines[key]) {
          final entity =
              await translate(key, mainJson[key], mainLanguage, language);
          translated.add(entity);
          print('Progress: ${translated.length}/$total');
        }
      }
      for (final file in files) {
        if (file == mainFile) continue;
        final currentFileName = getFileName(file.path);
        final currentContent = file.readAsStringSync();
        final currentJson =
            Map<String, String>.from(jsonDecode(currentContent));
        final currentLanguage = currentFileName.replaceAll('.json', '');
        final newWords =
            translated.where((e) => e.language == currentLanguage).toList();
        if (newWords.isEmpty) continue;
        for (final word in newWords) {
          if (currentJson[word.key] != null) continue;
          currentJson[word.key] = word.value;
        }

        final encoder = JsonEncoder.withIndent('	');
        final newJson = encoder.convert(currentJson);
        file.writeAsStringSync(newJson);
      }
    }

    Future<void> process(String inp, [String param]) async {
      if (inp == 'compare') {
        compare();
        return;
      }
      if (inp == 'sync') {
        final keysEquals = compare();
        if (!keysEquals) {
          print('Fix problems first');
          return;
        }
        await syncKeys(param);
        return;
      }
      print('Input $inp not recognized');
    }

    if (arguments.length > 1) {
      await process('sync');
      return;
    }

    if (arguments.length > 2) {
      final param = arguments.length > 3 ? arguments[3] : null;
      await process(arguments[2], param);
      return;
    }

    while (true) {
      print(
          '\nType compare or sync. You can pass key to sync, like `sync SOME_KEY`. In this case only 1 key will be translated.');
      final inp = readLine().trim();
      final splitted = inp.split(' ');
      final param = splitted.length > 1 ? splitted[1] : null;
      await process(splitted[0], param);
    }
  } catch (e) {
    print('panic error');
    print(e);
    rethrow;
  }
}

class TranslationEntity {
  final String language;
  final String key;
  final String value;

  TranslationEntity(this.language, this.key, this.value);
}

Future<TranslationEntity> translate(
  String key,
  String source,
  String sourceLang,
  String targetLang,
) async {
  final uri = Uri.https('api.mymemory.translated.net', '/get', {
    'q': source,
    'langpair':
        '${sourceLang.replaceAll('_', '-')}|${targetLang.replaceAll('_', '-')}',
    'key': 'f9295ed50b1119ebedae',
    'de': 'festeloqq@gmail.com'
  });
  final response = await http.get(uri);
  final json = jsonDecode(response.body);
  final text = json['responseData']['translatedText'];
  return TranslationEntity(targetLang, key, text);
}

String getFileName(String path) {
  return path.split(RegExp(r'\/|\\')).last;
}

String readLine() {
  return stdin.readLineSync();
}
