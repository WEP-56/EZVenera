import 'dart:convert';

import 'package:flutter_qjs/flutter_qjs.dart';

import '../engine/plugin_js_engine.dart';
import '../models.dart';
import '../result.dart';
import '../storage/plugin_data_store.dart';

class PluginSourceParser {
  PluginSourceParser({
    required this.engine,
    required this.dataStore,
    required this.appVersion,
  });

  final PluginJsEngine engine;
  final PluginDataStore dataStore;
  final String appVersion;

  String? _key;
  String? _name;

  Future<PluginSource> parse(
    String javascript, {
    required String filePath,
  }) async {
    await engine.ensureInitialized();
    final normalized = javascript.replaceAll('\r\n', '\n');
    final classLine = normalized
        .split('\n')
        .firstWhere(
          (line) => line.trim().startsWith('class '),
          orElse: () => '',
        );

    if (!classLine.contains('extends ComicSource')) {
      throw PluginSourceParseException(
        'Invalid source file: missing ComicSource class.',
      );
    }

    final className = classLine
        .split('class')
        .last
        .split('extends ComicSource')
        .first
        .trim();
    if (className.isEmpty) {
      throw PluginSourceParseException(
        'Invalid source file: class name not found.',
      );
    }

    await _resolve(
      engine.runCode('''
      (() => {
        $normalized
        this.__ez_temp_source = new $className();
      })();
    ''', '<plugin_parse>'),
    );

    _name =
        (await _resolve(engine.runCode('this.__ez_temp_source.name')))
            as String?;
    _key =
        (await _resolve(engine.runCode('this.__ez_temp_source.key')))
            as String?;
    final version =
        ((await _resolve(engine.runCode('this.__ez_temp_source.version')))
            as String?) ??
        '1.0.0';
    final minVersion =
        ((await _resolve(engine.runCode('this.__ez_temp_source.minAppVersion')))
            as String?) ??
        '0.0.0';
    final url =
        ((await _resolve(engine.runCode('this.__ez_temp_source.url')))
            as String?) ??
        '';

    if (_name == null || _name!.isEmpty) {
      throw PluginSourceParseException('Source name is required.');
    }
    if (_key == null || _key!.isEmpty) {
      throw PluginSourceParseException('Source key is required.');
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(_key!)) {
      throw PluginSourceParseException('Invalid source key: $_key');
    }
    if (engine.findSource(_key!) != null) {
      throw PluginSourceParseException('Duplicate source key: $_key');
    }
    if (_compareVersion(minVersion, appVersion) > 0) {
      throw PluginSourceParseException(
        'Source requires app version $minVersion or newer.',
      );
    }

    await _resolve(
      engine.runCode('ComicSource.sources.${_key!} = this.__ez_temp_source;'),
    );

    final source = PluginSource(
      name: _name!,
      key: _key!,
      version: version,
      minAppVersion: minVersion,
      url: url,
      filePath: filePath,
      data: await dataStore.read(_key!),
      persistData: (data) => dataStore.write(_key!, data),
      account: _parseAccount(),
      search: _parseSearch(),
      category: _parseCategory(),
      categoryComics: _parseCategoryComics(),
      comic: _parseComic(),
      settings: _parseSettings(),
      translations: _parseTranslations(),
      idMatcher: _parseIdMatcher(),
      link: _parseLink(),
      onTagSuggestionSelected: _parseTagSuggestionSelection(),
    );

    engine.registerSource(source);
    if (_existsSync('init')) {
      Future<void>.delayed(const Duration(milliseconds: 50), () async {
        await _resolve(engine.runCode('ComicSource.sources.${_key!}.init()'));
      });
    }

    return source;
  }

  PluginAccountCapability? _parseAccount() {
    if (!_existsSync('account')) {
      return null;
    }

    PluginLoginFunction? login;
    if (_existsSync('account.login')) {
      login = (account, password) async {
        try {
          await _resolve(
            engine.runCode('''
              ComicSource.sources.${_key!}.account.login(
                ${jsonEncode(account)},
                ${jsonEncode(password)}
              )
            '''),
          );
          final source = engine.findSource(_key!);
          source?.data['account'] = <String>[account, password];
          if (source != null) {
            await source.saveData();
          }
          return const PluginResult<bool>(true);
        } catch (error) {
          return PluginResult<bool>.error(error.toString());
        }
      };
    }

    PluginCookieValidationFunction? validateCookies;
    if (_existsSync('account.loginWithCookies?.validate')) {
      validateCookies = (values) async {
        try {
          final result = await _resolve(
            engine.runCode(
              'ComicSource.sources.${_key!}.account.loginWithCookies.validate(${jsonEncode(values)})',
            ),
          );
          return result == true;
        } catch (_) {
          return false;
        }
      };
    }

    return PluginAccountCapability(
      login: login,
      logout: () {
        engine.runCode('ComicSource.sources.${_key!}.account.logout()');
      },
      loginWebsite: _get('account.loginWithWebview?.url') as String?,
      registerWebsite: _get('account.registerWebsite') as String?,
      checkLoginStatus: _existsSync('account.loginWithWebview')
          ? (url, title) {
              final result = engine.runCode('''
                ComicSource.sources.${_key!}.account.loginWithWebview.checkStatus(
                  ${jsonEncode(url)},
                  ${jsonEncode(title)}
                )
              ''');
              return result == true;
            }
          : null,
      onWebviewLoginSuccess:
          _existsSync('account.loginWithWebview.onLoginSuccess')
          ? () {
              engine.runCode(
                'ComicSource.sources.${_key!}.account.loginWithWebview.onLoginSuccess()',
              );
            }
          : null,
      cookieFields: _stringList(_get('account.loginWithCookies?.fields')),
      validateCookies: validateCookies,
    );
  }

  PluginSearchCapability? _parseSearch() {
    if (!_existsSync('search')) {
      return null;
    }

    final options = <PluginSearchOption>[];
    for (final item
        in (_get('search.optionList') as List? ?? const <dynamic>[])) {
      if (item is! Map) {
        continue;
      }
      options.add(
        PluginSearchOption(
          label: item['label']?.toString() ?? '',
          type: item['type']?.toString() ?? 'select',
          options: _optionMap(item['options'] as List?),
          defaultValue: item['default'] == null
              ? null
              : jsonEncode(item['default']),
        ),
      );
    }

    PluginSearchLoadPage? loadPage;
    if (_existsSync('search.load')) {
      loadPage = (keyword, page, selectedOptions) async {
        try {
          final result = await _resolve(
            engine.runCode('''
              ComicSource.sources.${_key!}.search.load(
                ${jsonEncode(keyword)},
                ${jsonEncode(selectedOptions)},
                ${jsonEncode(page)}
              )
            '''),
          );
          return PluginResult<List<PluginComic>>(
            _comicList(result['comics'] as List),
            subData: result['maxPage'],
          );
        } catch (error) {
          return PluginResult<List<PluginComic>>.error(error.toString());
        }
      };
    }

    PluginSearchLoadNext? loadNext;
    if (!_existsSync('search.load') && _existsSync('search.loadNext')) {
      loadNext = (keyword, next, selectedOptions) async {
        try {
          final result = await _resolve(
            engine.runCode('''
              ComicSource.sources.${_key!}.search.loadNext(
                ${jsonEncode(keyword)},
                ${jsonEncode(selectedOptions)},
                ${jsonEncode(next)}
              )
            '''),
          );
          return PluginResult<List<PluginComic>>(
            _comicList(result['comics'] as List),
            subData: result['next'],
          );
        } catch (error) {
          return PluginResult<List<PluginComic>>.error(error.toString());
        }
      };
    }

    return PluginSearchCapability(
      options: options,
      loadPage: loadPage,
      loadNext: loadNext,
      enableTagSuggestions: _get('search.enableTagsSuggestions') == true,
    );
  }

  PluginCategoryCapability? _parseCategory() {
    final category = _get('category');
    if (category is! Map || category['title'] == null) {
      return null;
    }

    final parts = <PluginCategoryPart>[];
    for (final item in category['parts'] as List? ?? const <dynamic>[]) {
      if (item is! Map) {
        continue;
      }

      final name = item['name']?.toString() ?? '';
      final type = item['type']?.toString() ?? 'fixed';
      final categories = item['categories'];

      if (categories is List &&
          categories.isNotEmpty &&
          categories.first is Map) {
        final values = categories.whereType<Map>().map((entry) {
          return PluginCategoryItem(
            label: entry['label']?.toString() ?? '',
            target: _jumpTarget(entry['target']),
          );
        }).toList();

        if (type == 'random') {
          parts.add(
            PluginCategoryPart.random(
              name: name,
              items: values,
              randomNumber: (item['randomNumber'] as num?)?.toInt() ?? 1,
            ),
          );
        } else if (type == 'dynamic' && item['loader'] is JSInvokable) {
          final loader = JSAutoFreeFunction(item['loader'] as JSInvokable);
          parts.add(
            PluginCategoryPart.dynamic(
              name: name,
              dynamicLoader: () {
                final result = loader([]);
                if (result is! List) {
                  return const <PluginCategoryItem>[];
                }
                return result.whereType<Map>().map((entry) {
                  return PluginCategoryItem(
                    label: entry['label']?.toString() ?? '',
                    target: _jumpTarget(entry['target']),
                  );
                }).toList();
              },
            ),
          );
        } else {
          parts.add(PluginCategoryPart.fixed(name: name, items: values));
        }
        continue;
      }

      if (categories is! List) {
        continue;
      }

      final itemType = item['itemType']?.toString() ?? 'category';
      List<String>? params = _stringList(item['categoryParams']);
      final groupParam = item['groupParam']?.toString();
      if (groupParam != null) {
        params = List<String>.filled(categories.length, groupParam);
      }

      final values = <PluginCategoryItem>[];
      for (var index = 0; index < categories.length; index++) {
        final label = categories[index].toString();
        values.add(
          PluginCategoryItem(
            label: label,
            target: switch (itemType) {
              'search' => PluginJumpTarget(
                page: 'search',
                attributes: <String, dynamic>{'keyword': label},
              ),
              'search_with_namespace' => PluginJumpTarget(
                page: 'search',
                attributes: <String, dynamic>{'keyword': '$name:$label'},
              ),
              _ => PluginJumpTarget(
                page: 'category',
                attributes: <String, dynamic>{
                  'category': label,
                  'param': params?.elementAt(index),
                },
              ),
            },
          ),
        );
      }

      if (type == 'random') {
        parts.add(
          PluginCategoryPart.random(
            name: name,
            items: values,
            randomNumber: (item['randomNumber'] as num?)?.toInt() ?? 1,
          ),
        );
      } else {
        parts.add(PluginCategoryPart.fixed(name: name, items: values));
      }
    }

    return PluginCategoryCapability(
      title: category['title'].toString(),
      parts: parts,
      enableRankingPage: category['enableRankingPage'] == true,
    );
  }

  PluginCategoryComicsCapability? _parseCategoryComics() {
    if (!_existsSync('categoryComics')) {
      return null;
    }

    final options = <PluginCategoryComicsOption>[];
    for (final item
        in (_get('categoryComics.optionList') as List? ?? const <dynamic>[])) {
      if (item is! Map) {
        continue;
      }
      options.add(
        PluginCategoryComicsOption(
          label: item['label']?.toString() ?? '',
          options: _optionMap(item['options'] as List?),
          notShowWhen: _stringList(item['notShowWhen']) ?? const <String>[],
          showWhen: _stringList(item['showWhen']),
        ),
      );
    }

    PluginRankingCapability? ranking;
    if (_existsSync('categoryComics.ranking.load')) {
      ranking = PluginRankingCapability(
        options: _optionMap(_get('categoryComics.ranking.options') as List?),
        load: (option, page) async {
          try {
            final result = await _resolve(
              engine.runCode('''
                ComicSource.sources.${_key!}.categoryComics.ranking.load(
                  ${jsonEncode(option)},
                  ${jsonEncode(page)}
                )
              '''),
            );
            return PluginResult<List<PluginComic>>(
              _comicList(result['comics'] as List),
              subData: result['maxPage'],
            );
          } catch (error) {
            return PluginResult<List<PluginComic>>.error(error.toString());
          }
        },
      );
    }

    return PluginCategoryComicsCapability(
      options: options,
      ranking: ranking,
      load: (category, param, selectedOptions, page) async {
        try {
          final result = await _resolve(
            engine.runCode('''
              ComicSource.sources.${_key!}.categoryComics.load(
                ${jsonEncode(category)},
                ${jsonEncode(param)},
                ${jsonEncode(selectedOptions)},
                ${jsonEncode(page)}
              )
            '''),
          );
          return PluginResult<List<PluginComic>>(
            _comicList(result['comics'] as List),
            subData: result['maxPage'],
          );
        } catch (error) {
          return PluginResult<List<PluginComic>>.error(error.toString());
        }
      },
    );
  }

  PluginComicCapability? _parseComic() {
    if (!_existsSync('comic.loadInfo') || !_existsSync('comic.loadEp')) {
      return null;
    }

    return PluginComicCapability(
      loadInfo: (id) async {
        try {
          final result = await _resolve(
            engine.runCode(
              'ComicSource.sources.${_key!}.comic.loadInfo(${jsonEncode(id)})',
            ),
          );
          if (result is! Map) {
            return const PluginResult<PluginComicDetails>.error(
              'Invalid comic info result.',
            );
          }
          return PluginResult<PluginComicDetails>(
            _comicDetails(Map<String, dynamic>.from(result), id),
          );
        } catch (error) {
          return PluginResult<PluginComicDetails>.error(error.toString());
        }
      },
      loadEpisode: (comicId, episodeId) async {
        try {
          final result = await _resolve(
            engine.runCode('''
              ComicSource.sources.${_key!}.comic.loadEp(
                ${jsonEncode(comicId)},
                ${jsonEncode(episodeId)}
              )
            '''),
          );
          return PluginResult<List<String>>(
            List<String>.from(result['images'] as List),
          );
        } catch (error) {
          return PluginResult<List<String>>.error(error.toString());
        }
      },
      onImageLoad: _existsSync('comic.onImageLoad')
          ? (imageKey, comicId, episodeId) async {
              final result = await _resolve(
                engine.runCode('''
                  ComicSource.sources.${_key!}.comic.onImageLoad(
                    ${jsonEncode(imageKey)},
                    ${jsonEncode(comicId)},
                    ${jsonEncode(episodeId)}
                  )
                '''),
              );
              return _imageRequest(result);
            }
          : null,
      onThumbnailLoad: _existsSync('comic.onThumbnailLoad')
          ? (imageKey) {
              final result = engine.runCode(
                'ComicSource.sources.${_key!}.comic.onThumbnailLoad(${jsonEncode(imageKey)})',
              );
              return _imageRequest(result);
            }
          : null,
    );
  }

  Map<String, PluginSourceSetting> _parseSettings() {
    final settings = _get('settings');
    if (settings is! Map) {
      return const <String, PluginSourceSetting>{};
    }

    final result = <String, PluginSourceSetting>{};
    for (final entry in settings.entries) {
      if (entry.key is! String || entry.value is! Map) {
        continue;
      }
      final value = entry.value as Map;
      final type = value['type']?.toString() ?? '';
      if (!const <String>{'select', 'switch', 'input'}.contains(type)) {
        continue;
      }
      result[entry.key as String] = PluginSourceSetting(
        key: entry.key as String,
        title: value['title']?.toString() ?? entry.key as String,
        type: type,
        defaultValue: value['default'],
        validator: value['validator']?.toString(),
        options: (value['options'] as List? ?? const <dynamic>[])
            .whereType<Map>()
            .map((option) {
              return PluginSettingOption(
                value: option['value']?.toString() ?? '',
                text:
                    option['text']?.toString() ??
                    option['value']?.toString() ??
                    '',
              );
            })
            .toList(),
      );
    }
    return result;
  }

  Map<String, Map<String, String>> _parseTranslations() {
    final translation = _get('translation');
    if (translation is! Map) {
      return const <String, Map<String, String>>{};
    }
    final result = <String, Map<String, String>>{};
    for (final entry in translation.entries) {
      if (entry.key is! String || entry.value is! Map) {
        continue;
      }
      result[entry.key as String] = Map<String, String>.from(
        entry.value as Map,
      );
    }
    return result;
  }

  RegExp? _parseIdMatcher() {
    return _existsSync('comic.idMatch')
        ? RegExp(_get('comic.idMatch').toString())
        : null;
  }

  PluginLinkCapability? _parseLink() {
    if (!_existsSync('comic.link')) {
      return null;
    }
    return PluginLinkCapability(
      domains: _stringList(_get('comic.link.domains')) ?? const <String>[],
      linkToId: (url) {
        final result = engine.runCode(
          'ComicSource.sources.${_key!}.comic.link.linkToId(${jsonEncode(url)})',
        );
        return result?.toString();
      },
    );
  }

  PluginTagSuggestionSelect? _parseTagSuggestionSelection() {
    if (!_existsSync('search.onTagSuggestionSelected')) {
      return null;
    }
    return (namespace, tag) {
      final result = engine.runCode('''
        ComicSource.sources.${_key!}.search.onTagSuggestionSelected(
          ${jsonEncode(namespace)},
          ${jsonEncode(tag)}
        )
      ''');
      return result?.toString() ?? '$namespace:$tag';
    };
  }

  PluginImageRequest _imageRequest(dynamic value) {
    if (value is! Map) {
      return const PluginImageRequest();
    }
    return PluginImageRequest(
      url: value['url']?.toString(),
      method: value['method']?.toString(),
      data: value['data'],
      headers: Map<String, dynamic>.from(
        value['headers'] ?? const <String, dynamic>{},
      ),
      onResponse: value['onResponse'] is JSInvokable
          ? JSAutoFreeFunction(value['onResponse'] as JSInvokable)
          : null,
      modifyImageScript: value['modifyImage']?.toString(),
      onLoadFailed: value['onLoadFailed'] is JSInvokable
          ? JSAutoFreeFunction(value['onLoadFailed'] as JSInvokable)
          : null,
    );
  }

  PluginJumpTarget _jumpTarget(dynamic value) {
    if (value is Map && value['page'] != null) {
      return PluginJumpTarget(
        page: value['page'].toString(),
        attributes: value['attributes'] == null
            ? null
            : Map<String, dynamic>.from(value['attributes'] as Map),
      );
    }
    if (value is Map && value['action'] != null) {
      return PluginJumpTarget(
        page: value['action'].toString(),
        attributes: <String, dynamic>{
          'keyword': value['keyword'],
          'param': value['param'],
        },
      );
    }
    if (value is String && value.contains(':')) {
      final parts = value.split(':');
      final page = parts.first;
      final payload = parts.sublist(1).join(':');
      if (page == 'category' && payload.contains('@')) {
        final categoryParts = payload.split('@');
        return PluginJumpTarget(
          page: page,
          attributes: <String, dynamic>{
            'category': categoryParts[0],
            'param': categoryParts[1],
          },
        );
      }
      return PluginJumpTarget(
        page: page,
        attributes: <String, dynamic>{
          page == 'category' ? 'category' : 'keyword': payload,
        },
      );
    }
    return const PluginJumpTarget(page: 'unknown');
  }

  List<PluginComic> _comicList(List<dynamic> values) {
    return values.whereType<Map>().map((item) {
      final map = Map<String, dynamic>.from(item);
      return PluginComic(
        id: map['id'].toString(),
        title: map['title']?.toString() ?? '',
        cover: map['cover']?.toString() ?? '',
        sourceKey: _key!,
        subtitle: map['subtitle']?.toString() ?? map['subTitle']?.toString(),
        tags: _stringList(map['tags']),
        description: map['description']?.toString() ?? '',
        maxPage: (map['maxPage'] as num?)?.toInt(),
        language: map['language']?.toString(),
        favoriteId: map['favoriteId']?.toString(),
        stars: (map['stars'] as num?)?.toDouble(),
      );
    }).toList();
  }

  PluginComicDetails _comicDetails(Map<String, dynamic> value, String id) {
    return PluginComicDetails(
      id: id,
      sourceKey: _key!,
      title: value['title']?.toString() ?? '',
      subtitle: value['subtitle']?.toString() ?? value['subTitle']?.toString(),
      cover: value['cover']?.toString() ?? '',
      description: value['description']?.toString(),
      tags: _tagMap(value['tags']),
      chapters: _chapters(value['chapters']),
      thumbnails: _stringList(value['thumbnails']),
      subId: value['subId']?.toString(),
      url: value['url']?.toString(),
      maxPage: (value['maxPage'] as num?)?.toInt(),
    );
  }

  Map<String, List<String>> _tagMap(dynamic value) {
    if (value is! Map) {
      return const <String, List<String>>{};
    }
    final result = <String, List<String>>{};
    for (final entry in value.entries) {
      if (entry.key is String && entry.value is List) {
        result[entry.key as String] = List<String>.from(entry.value as List);
      }
    }
    return result;
  }

  PluginComicChapters? _chapters(dynamic value) {
    if (value is! Map) {
      return null;
    }
    final flat = <String, String>{};
    final grouped = <String, Map<String, String>>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        continue;
      }
      if (entry.value is Map) {
        grouped[entry.key as String] = Map<String, String>.from(
          entry.value as Map,
        );
      } else {
        flat[entry.key as String] = entry.value.toString();
      }
    }
    if (flat.isNotEmpty) {
      return PluginComicChapters.flat(flat);
    }
    if (grouped.isNotEmpty) {
      return PluginComicChapters.grouped(grouped);
    }
    return null;
  }

  Map<String, String> _optionMap(List<dynamic>? values) {
    final result = <String, String>{};
    for (final item in values ?? const <dynamic>[]) {
      if (item is! String || !item.contains('-')) {
        continue;
      }
      final parts = item.split('-');
      final key = parts.removeAt(0);
      result[key] = parts.join('-');
    }
    return result;
  }

  List<String>? _stringList(dynamic value) {
    if (value is! List) {
      return null;
    }
    return value.map((item) => item.toString()).toList();
  }

  bool _existsSync(String path) {
    final result = engine.runCode(
      'ComicSource.sources.${_key!}.$path !== null && ComicSource.sources.${_key!}.$path !== undefined',
    );
    return result == true;
  }

  dynamic _get(String path) {
    return engine.runCode('ComicSource.sources.${_key!}.$path');
  }

  Future<dynamic> _resolve(dynamic value) async {
    if (value is Future) {
      return await value;
    }
    return value;
  }

  int _compareVersion(String left, String right) {
    final a = left.replaceFirst('-', '.').split('.');
    final b = right.replaceFirst('-', '.').split('.');
    for (var index = 0; index < 3; index++) {
      final leftNumber = int.tryParse(a.elementAt(index)) ?? 0;
      final rightNumber = int.tryParse(b.elementAt(index)) ?? 0;
      if (leftNumber != rightNumber) {
        return leftNumber.compareTo(rightNumber);
      }
    }
    return 0;
  }
}

class PluginSourceParseException implements Exception {
  PluginSourceParseException(this.message);

  final String message;

  @override
  String toString() => message;
}
