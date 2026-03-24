enum BizLogTag {
  wallpaper('wallpaper'),
  wakeword('wakeword');

  final String value;
  const BizLogTag(this.value);

  String get tag => value;
}
