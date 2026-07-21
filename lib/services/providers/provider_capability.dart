/// The task categories a provider can serve. The router maps every
/// [ChatRoute] onto one capability and then asks the registry which
/// key-present provider is preferred for it (the "Auto" decision).
enum ProviderCapability {
  /// General conversational text.
  chat,

  /// Code generation / the Code Studio.
  code,

  /// Long-form / marketing writing (Copy & Scripts).
  writing,

  /// Prompt classification used by the model router itself.
  routing,

  /// Still-image generation (Image Studio).
  image,

  /// Video generation (Video Studio).
  video,

  /// Talking-avatar generation (Voice & Avatar Studio).
  avatar,

  /// Grounded / web-search-backed answering (Deep Research).
  search,

  /// Text-to-speech voice output.
  voice,
}

/// How a provider authenticates a request.
enum AuthScheme {
  /// Key travels in a request header (Anthropic `x-api-key`, OpenAI-style
  /// `Authorization: Bearer`).
  header,

  /// Key travels as a URL query parameter (Gemini `?key=`).
  queryParam,
}

/// Which concrete client implementation drives a descriptor. One client is
/// built (and cached) per kind by the `ClientRegistry`; several descriptors
/// (OpenAI, Groq, OpenRouter, Mistral) share the single `openAiCompatible`
/// client, differing only by descriptor data.
enum ProviderClientKind {
  anthropic,
  gemini,
  openAiCompatible,
  flux,
  heygen,
}
