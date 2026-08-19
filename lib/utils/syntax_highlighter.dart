import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show highlight, Node;

// ─────────────────────────────────────────────────────────────────────────────
// VS Code Dark+ Theme Map for highlight.js nodes
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, TextStyle> vsCodeDarkPlusTheme = {
  'root': TextStyle(color: Color(0xFFD4D4D4), backgroundColor: Colors.transparent),
  'keyword': TextStyle(color: Color(0xFF569CD6), fontWeight: FontWeight.bold),
  'built_in': TextStyle(color: Color(0xFF4EC9B0)),
  'type': TextStyle(color: Color(0xFF4EC9B0)),
  'literal': TextStyle(color: Color(0xFF569CD6)),
  'number': TextStyle(color: Color(0xFFB5CEA8)),
  'regexp': TextStyle(color: Color(0xFFD16969)),
  'string': TextStyle(color: Color(0xFFCE9178)),
  'subst': TextStyle(color: Color(0xFF9CDCFE)),
  'symbol': TextStyle(color: Color(0xFF4EC9B0)),
  'class': TextStyle(color: Color(0xFF4EC9B0)),
  'function': TextStyle(color: Color(0xFFDCDCAA)),
  'title': TextStyle(color: Color(0xFFDCDCAA)),
  'title.function': TextStyle(color: Color(0xFFDCDCAA)),
  'title.class': TextStyle(color: Color(0xFF4EC9B0)),
  'params': TextStyle(color: Color(0xFF9CDCFE)),
  'comment': TextStyle(color: Color(0xFF6A9955), fontStyle: FontStyle.italic),
  'doctag': TextStyle(color: Color(0xFF608B4E)),
  'meta': TextStyle(color: Color(0xFF9B9B9B)),
  'meta-keyword': TextStyle(color: Color(0xFF569CD6)),
  'meta-string': TextStyle(color: Color(0xFFCE9178)),
  'section': TextStyle(color: Color(0xFF569CD6), fontWeight: FontWeight.bold),
  'tag': TextStyle(color: Color(0xFF569CD6)),
  'name': TextStyle(color: Color(0xFF569CD6)),
  'attr': TextStyle(color: Color(0xFF9CDCFE)),
  'attribute': TextStyle(color: Color(0xFF9CDCFE)),
  'variable': TextStyle(color: Color(0xFF9CDCFE)),
  'variable.language': TextStyle(color: Color(0xFF569CD6)),
  'bullet': TextStyle(color: Color(0xFFD7BA7D)),
  'code': TextStyle(color: Color(0xFFCE9178)),
  'emphasis': TextStyle(fontStyle: FontStyle.italic),
  'strong': TextStyle(fontWeight: FontWeight.bold),
  'formula': TextStyle(color: Color(0xFFD7BA7D)),
  'link': TextStyle(color: Color(0xFF9CDCFE), decoration: TextDecoration.underline),
  'quote': TextStyle(color: Color(0xFF6A9955)),
  'selector-tag': TextStyle(color: Color(0xFFD7BA7D)),
  'selector-id': TextStyle(color: Color(0xFFD7BA7D)),
  'selector-class': TextStyle(color: Color(0xFFD7BA7D)),
  'selector-attr': TextStyle(color: Color(0xFFD7BA7D)),
  'selector-pseudo': TextStyle(color: Color(0xFFD7BA7D)),
  'template-tag': TextStyle(color: Color(0xFF569CD6)),
  'template-variable': TextStyle(color: Color(0xFF9CDCFE)),
  'addition': TextStyle(color: Color(0xFFB5CEA8), backgroundColor: Color(0x22B5CEA8)),
  'deletion': TextStyle(color: Color(0xFFCE9178), backgroundColor: Color(0x22CE9178)),
};

/// A [TextEditingController] that performs syntax highlighting in real-time
/// using the `highlight` parser while preserving all standard editing features.
class SyntaxHighlightingController extends TextEditingController {
  SyntaxHighlightingController({
    super.text,
    this.language,
    this.theme = vsCodeDarkPlusTheme,
  });

  String? language;
  Map<String, TextStyle> theme;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final lang = language;
    if (lang == null || lang.isEmpty || text.isEmpty) {
      return TextSpan(style: style, text: text);
    }

    try {
      final parsed = highlight.parse(text, language: lang, autoDetection: false);
      final nodes = parsed.nodes;
      if (nodes == null || nodes.isEmpty) {
        return TextSpan(style: style, text: text);
      }

      return TextSpan(
        style: style,
        children: _convertNodes(nodes, style),
      );
    } catch (_) {
      // If language is not supported or parsing fails, gracefully fall back to base style
      return TextSpan(style: style, text: text);
    }
  }

  List<TextSpan> _convertNodes(List<Node> nodes, TextStyle? baseStyle) {
    final List<TextSpan> spans = [];

    for (final node in nodes) {
      final nodeValue = node.value;
      final nodeChildren = node.children;
      final className = node.className;

      TextStyle? nodeStyle = baseStyle;
      if (className != null && theme.containsKey(className)) {
        nodeStyle = baseStyle?.merge(theme[className]) ?? theme[className];
      }

      if (nodeValue != null) {
        spans.add(TextSpan(text: nodeValue, style: nodeStyle));
      } else if (nodeChildren != null && nodeChildren.isNotEmpty) {
        spans.add(TextSpan(
          style: nodeStyle,
          children: _convertNodes(nodeChildren, nodeStyle),
        ));
      }
    }

    return spans;
  }
}
