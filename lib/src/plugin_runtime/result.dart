class PluginResult<T> {
  const PluginResult(this._data, {this.errorMessage, this.subData});

  const PluginResult.error(String this.errorMessage)
    : _data = null,
      subData = null;

  final T? _data;
  final String? errorMessage;
  final dynamic subData;

  bool get isError => errorMessage != null;

  bool get isSuccess => !isError;

  T get data => _data ?? (throw StateError(errorMessage ?? 'Unknown error'));

  T? get dataOrNull => _data;
}
