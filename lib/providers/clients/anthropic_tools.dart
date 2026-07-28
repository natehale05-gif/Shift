/// Anthropic server-tool definitions (they execute on Anthropic's
/// infrastructure — nothing runs client-side).
class AnthropicTools {
  AnthropicTools._();

  /// Web search with built-in dynamic filtering — no beta header needed.
  static const Map<String, dynamic> webSearch = {
    'type': 'web_search_20260209',
    'name': 'web_search',
    'max_uses': 5,
  };

  static const Map<String, dynamic> codeExecution = {
    'type': 'code_execution_20260521',
    'name': 'code_execution',
  };

  /// Beta flag required when the standalone code-execution tool is included.
  static const codeExecutionBeta = 'code-execution-2025-08-25';

  /// Human label for a server tool's progress chip.
  static String labelFor(String toolName) => switch (toolName) {
        'web_search' => 'Searching the web…',
        'web_fetch' => 'Reading a page…',
        'code_execution' ||
        'bash_code_execution' =>
          'Running code…',
        'text_editor_code_execution' => 'Editing files…',
        _ => 'Using $toolName…',
      };
}
