enum BizLogTag {
  buy('buy'),
  wallpaper('wallpaper'),
  wakeword('wakeword');

  final String value;
  const BizLogTag(this.value);

  String get tag => value;
}
