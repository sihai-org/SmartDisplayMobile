class PurchaseUiProductItem {
  const PurchaseUiProductItem({
    required this.id,
    required this.title,
    required this.priceText,
    this.remark,
  });

  final String id;
  final String title;
  final String priceText;
  final String? remark;
}
