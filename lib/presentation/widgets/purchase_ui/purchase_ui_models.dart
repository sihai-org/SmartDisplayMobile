class PurchaseUiProductItem {
  const PurchaseUiProductItem({
    required this.id,
    required this.title,
    required this.priceText,
    required this.supportingText,
    this.subtitle,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String priceText;
  final String supportingText;
}
