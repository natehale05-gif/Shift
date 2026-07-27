/// Token usage for one assistant turn, reported by real providers.
/// The mock reports plausible numbers so the UI path stays exercised.
class UsageReport {
  final int inputTokens;
  final int outputTokens;
  final String model;

  const UsageReport({
    required this.inputTokens,
    required this.outputTokens,
    required this.model,
  });

  factory UsageReport.fromJson(Map<String, dynamic> json) => UsageReport(
        inputTokens: json['inputTokens'] as int,
        outputTokens: json['outputTokens'] as int,
        model: json['model'] as String,
      );

  Map<String, dynamic> toJson() => {
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'model': model,
      };
}
