/// A web source backing part of an assistant reply (from web search or
/// grounding). Rendered as numbered chips under the message.
class Citation {
  final String url;
  final String title;
  final String? citedText;

  const Citation({required this.url, required this.title, this.citedText});

  factory Citation.fromJson(Map<String, dynamic> json) => Citation(
        url: json['url'] as String,
        title: json['title'] as String,
        citedText: json['citedText'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'citedText': citedText,
      };
}
