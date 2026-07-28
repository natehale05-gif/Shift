/// Whether a request is asking for a diagram, which is answered with a
/// ```mermaid fence rendered live in the reply.
///
/// Pure and shared: the turn planner needs this decision, and it is not
/// specific to simulated or live answers.
library;

final RegExp _diagramRe = RegExp(
  r'\b(diagram|flow ?chart|flow ?diagram|sequence diagram|mind ?map|'
  r'gantt|org ?chart|class diagram|state diagram|er diagram)\b',
  caseSensitive: false,
);

bool wantsDiagram(String input) => _diagramRe.hasMatch(input);
