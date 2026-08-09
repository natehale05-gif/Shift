/// What a step needs a provider to be able to do.
///
/// **Capabilities, not providers.** A step says "I need an image made"; which
/// model makes it is decided later, from what the account can actually pay for
/// and what is available. This indirection is the whole reason models can
/// collaborate on one request without any pairing being special-cased: the
/// picture step resolves to whichever image provider is best, the page step to
/// whichever text provider is, and neither knows about the other.
///
/// v1 did this with a table of eight hard-coded studio combinations matched by
/// keyword. It worked for the eight and could not generalise — every new
/// pairing was a new enum arm and a new keyword list.
enum Capability {
  /// Prose, answers, code, structured JSON — anything a language model writes.
  text,

  /// Still images, generated or edited.
  image,

  /// Moving pictures. Asynchronous almost everywhere: submit, then poll.
  video,

  /// Text to speech.
  speech,

  /// Music and sound beds.
  music,

  /// Speech to text.
  transcription,

  /// Searching the live web. Distinct from [text] because a provider can be
  /// excellent at writing and have no search at all.
  search,

  /// Turning content into a real file — pptx, docx, xlsx, pdf. Runs locally
  /// rather than at a provider, and is a capability so the graph can depend on
  /// it like anything else.
  document,
}
