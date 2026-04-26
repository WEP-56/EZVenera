import 'package:flutter_qjs/flutter_qjs.dart';

import 'result.dart';

typedef PluginLoginFunction =
    Future<PluginResult<bool>> Function(String account, String password);
typedef PluginCookieValidationFunction =
    Future<bool> Function(List<String> values);
typedef PluginWebviewLoginSuccess = Future<void> Function();
typedef PluginSearchLoadPage =
    Future<PluginResult<List<PluginComic>>> Function(
      String keyword,
      int page,
      List<String> options,
    );
typedef PluginSearchLoadNext =
    Future<PluginResult<List<PluginComic>>> Function(
      String keyword,
      String? next,
      List<String> options,
    );
typedef PluginCategoryComicsLoader =
    Future<PluginResult<List<PluginComic>>> Function(
      String category,
      String? param,
      List<String> options,
      int page,
    );
typedef PluginCategoryOptionsLoader =
    Future<PluginResult<List<PluginCategoryComicsOption>>> Function(
      String category,
      String? param,
    );
typedef PluginRankingLoader =
    Future<PluginResult<List<PluginComic>>> Function(String option, int page);
typedef PluginRankingLoadNext =
    Future<PluginResult<List<PluginComic>>> Function(String option, String? next);
typedef PluginComicInfoLoader =
    Future<PluginResult<PluginComicDetails>> Function(String id);
typedef PluginComicPagesLoader =
    Future<PluginResult<List<String>>> Function(
      String comicId,
      String? episodeId,
    );
typedef PluginImageConfigLoader =
    Future<PluginImageRequest> Function(
      String imageKey,
      String comicId,
      String episodeId,
    );
typedef PluginThumbnailConfigLoader =
    PluginImageRequest Function(String imageKey);
typedef PluginDynamicCategoryLoader = List<PluginCategoryItem> Function();
typedef PluginTagSuggestionSelect =
    String Function(String namespace, String tag);

class PluginSource {
  PluginSource({
    required this.name,
    required this.key,
    required this.version,
    required this.minAppVersion,
    required this.url,
    required this.filePath,
    required this.data,
    required this.persistData,
    this.account,
    this.search,
    this.category,
    this.categoryComics,
    this.comic,
    this.settings = const {},
    this.translations = const {},
    this.idMatcher,
    this.link,
    this.onTagSuggestionSelected,
  });

  final String name;
  final String key;
  final String version;
  final String minAppVersion;
  final String url;
  final String filePath;
  final Map<String, dynamic> data;
  final Future<void> Function(Map<String, dynamic> data) persistData;
  final PluginAccountCapability? account;
  final PluginSearchCapability? search;
  final PluginCategoryCapability? category;
  final PluginCategoryComicsCapability? categoryComics;
  final PluginComicCapability? comic;
  final Map<String, PluginSourceSetting> settings;
  final Map<String, Map<String, String>> translations;
  final RegExp? idMatcher;
  final PluginLinkCapability? link;
  final PluginTagSuggestionSelect? onTagSuggestionSelected;

  String get updateUrl {
    final installSourceUrl = data['_installSourceUrl']?.toString().trim() ?? '';
    if (installSourceUrl.isNotEmpty) {
      return installSourceUrl;
    }
    return url.trim();
  }

  bool get isLogged {
    if (data['_ez_logged'] == true || data['account'] != null) {
      return true;
    }
    final localStorage = data['_localStorage'];
    return localStorage is Map && localStorage.isNotEmpty;
  }

  void markLoggedIn({dynamic accountData}) {
    data['_ez_logged'] = true;
    if (accountData != null) {
      data['account'] = accountData;
    }
  }

  void markLoggedOut() {
    data['_ez_logged'] = false;
    data.remove('account');
    data.remove('_localStorage');
  }

  Future<void> saveData() => persistData(data);

  String translate(String text, String locale) {
    return translations[locale]?[text] ?? text;
  }
}

class PluginAccountCapability {
  const PluginAccountCapability({
    required this.logout,
    this.login,
    this.loginWebsite,
    this.registerWebsite,
    this.checkLoginStatus,
    this.onWebviewLoginSuccess,
    this.cookieFields,
    this.validateCookies,
  });

  final PluginLoginFunction? login;
  final void Function() logout;
  final String? loginWebsite;
  final String? registerWebsite;
  final bool Function(String url, String title)? checkLoginStatus;
  final PluginWebviewLoginSuccess? onWebviewLoginSuccess;
  final List<String>? cookieFields;
  final PluginCookieValidationFunction? validateCookies;
}

class PluginSearchCapability {
  const PluginSearchCapability({
    required this.options,
    this.loadPage,
    this.loadNext,
    this.enableTagSuggestions = false,
  });

  final List<PluginSearchOption> options;
  final PluginSearchLoadPage? loadPage;
  final PluginSearchLoadNext? loadNext;
  final bool enableTagSuggestions;
}

class PluginSearchOption {
  const PluginSearchOption({
    required this.label,
    required this.type,
    required this.options,
    this.defaultValue,
  });

  final String label;
  final String type;
  final Map<String, String> options;
  final String? defaultValue;
}

class PluginCategoryCapability {
  const PluginCategoryCapability({
    required this.title,
    required this.parts,
    this.enableRankingPage = false,
  });

  final String title;
  final List<PluginCategoryPart> parts;
  final bool enableRankingPage;
}

class PluginCategoryPart {
  const PluginCategoryPart.fixed({required this.name, required this.items})
    : type = PluginCategoryPartType.fixed,
      randomNumber = null,
      dynamicLoader = null;

  const PluginCategoryPart.random({
    required this.name,
    required this.items,
    required this.randomNumber,
  }) : type = PluginCategoryPartType.random,
       dynamicLoader = null;

  const PluginCategoryPart.dynamic({
    required this.name,
    required this.dynamicLoader,
  }) : type = PluginCategoryPartType.dynamic,
       items = const [],
       randomNumber = null;

  final String name;
  final PluginCategoryPartType type;
  final List<PluginCategoryItem> items;
  final int? randomNumber;
  final PluginDynamicCategoryLoader? dynamicLoader;
}

enum PluginCategoryPartType { fixed, random, dynamic }

class PluginCategoryItem {
  const PluginCategoryItem({required this.label, required this.target});

  final String label;
  final PluginJumpTarget target;
}

class PluginJumpTarget {
  const PluginJumpTarget({required this.page, this.attributes});

  final String page;
  final Map<String, dynamic>? attributes;
}

class PluginCategoryComicsCapability {
  const PluginCategoryComicsCapability({
    required this.load,
    required this.options,
    this.optionsLoader,
    this.ranking,
  });

  final PluginCategoryComicsLoader load;
  final List<PluginCategoryComicsOption> options;
  final PluginCategoryOptionsLoader? optionsLoader;
  final PluginRankingCapability? ranking;
}

class PluginCategoryComicsOption {
  const PluginCategoryComicsOption({
    required this.label,
    required this.options,
    this.notShowWhen = const [],
    this.showWhen,
  });

  final String label;
  final Map<String, String> options;
  final List<String> notShowWhen;
  final List<String>? showWhen;
}

class PluginRankingCapability {
  const PluginRankingCapability({
    required this.options,
    this.load,
    this.loadNext,
  });

  final Map<String, String> options;
  final PluginRankingLoader? load;
  final PluginRankingLoadNext? loadNext;
}

class PluginComicCapability {
  const PluginComicCapability({
    required this.loadInfo,
    required this.loadEpisode,
    this.onImageLoad,
    this.onThumbnailLoad,
  });

  final PluginComicInfoLoader loadInfo;
  final PluginComicPagesLoader loadEpisode;
  final PluginImageConfigLoader? onImageLoad;
  final PluginThumbnailConfigLoader? onThumbnailLoad;
}

class PluginComic {
  const PluginComic({
    required this.id,
    required this.title,
    required this.cover,
    required this.sourceKey,
    this.subtitle,
    this.tags,
    this.description = '',
    this.maxPage,
    this.language,
    this.favoriteId,
    this.stars,
  });

  final String id;
  final String title;
  final String cover;
  final String sourceKey;
  final String? subtitle;
  final List<String>? tags;
  final String description;
  final int? maxPage;
  final String? language;
  final String? favoriteId;
  final double? stars;
}

class PluginComicDetails {
  const PluginComicDetails({
    required this.id,
    required this.sourceKey,
    required this.title,
    required this.cover,
    required this.tags,
    this.subtitle,
    this.description,
    this.chapters,
    this.thumbnails,
    this.subId,
    this.url,
    this.maxPage,
  });

  final String id;
  final String sourceKey;
  final String title;
  final String cover;
  final Map<String, List<String>> tags;
  final String? subtitle;
  final String? description;
  final PluginComicChapters? chapters;
  final List<String>? thumbnails;
  final String? subId;
  final String? url;
  final int? maxPage;
}

class PluginComicChapters {
  const PluginComicChapters.flat(this.chapters) : groupedChapters = null;

  const PluginComicChapters.grouped(this.groupedChapters) : chapters = null;

  final Map<String, String>? chapters;
  final Map<String, Map<String, String>>? groupedChapters;

  bool get isGrouped => groupedChapters != null;
}

class PluginImageRequest {
  const PluginImageRequest({
    this.url,
    this.method,
    this.data,
    this.headers = const {},
    this.onResponse,
    this.modifyImageScript,
    this.onLoadFailed,
  });

  final String? url;
  final String? method;
  final dynamic data;
  final Map<String, dynamic> headers;
  final JSAutoFreeFunction? onResponse;
  final String? modifyImageScript;
  final JSAutoFreeFunction? onLoadFailed;
}

class PluginLinkCapability {
  const PluginLinkCapability({required this.domains, required this.linkToId});

  final List<String> domains;
  final String? Function(String url) linkToId;
}

class PluginSourceSetting {
  const PluginSourceSetting({
    required this.key,
    required this.title,
    required this.type,
    this.options = const [],
    this.defaultValue,
    this.validator,
  });

  final String key;
  final String title;
  final String type;
  final List<PluginSettingOption> options;
  final dynamic defaultValue;
  final String? validator;
}

class PluginSettingOption {
  const PluginSettingOption({required this.value, required this.text});

  final String value;
  final String text;
}

class JSAutoFreeFunction {
  JSAutoFreeFunction(this.func) {
    func.dup();
    _finalizer.attach(this, func);
  }

  final JSInvokable func;

  dynamic call(List<dynamic> args) => func(args);

  static final Finalizer<JSInvokable> _finalizer = Finalizer<JSInvokable>((
    JSInvokable func,
  ) {
    func.destroy();
  });
}
