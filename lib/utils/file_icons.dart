import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FileIcons — Centralised file-type icon + color mapping.
//
// Covers 40+ extensions across web, backend, systems, mobile, data, config,
// docs, media, and shell categories.  Uses Material Icons with colours that
// match the VS Code Material Icon Theme.
// ─────────────────────────────────────────────────────────────────────────────

class FileIconInfo {
  final IconData icon;
  final Color color;

  const FileIconInfo(this.icon, this.color);
}

class FileIcons {
  FileIcons._();

  /// Returns the icon + colour for a given filename.
  static FileIconInfo forFile(String filename) {
    final lower = filename.toLowerCase();

    // ── Special filenames ──────────────────────────────────────────────────
    if (lower == 'dockerfile') return const FileIconInfo(Icons.directions_boat_rounded, Color(0xFF2496ED));
    if (lower == '.gitignore' || lower == '.gitattributes') return const FileIconInfo(Icons.merge_type_rounded, Color(0xFFF05032));
    if (lower == '.env' || lower.startsWith('.env.')) return const FileIconInfo(Icons.key_rounded, Color(0xFFFFC107));
    if (lower == 'makefile' || lower == 'cmakelists.txt') return const FileIconInfo(Icons.build_rounded, Color(0xFFE65100));
    if (lower == '.dockerignore') return const FileIconInfo(Icons.directions_boat_rounded, Color(0xFF2496ED));
    if (lower == 'license' || lower == 'licence') return const FileIconInfo(Icons.gavel_rounded, Color(0xFFFFCA28));
    if (lower == 'readme.md') return const FileIconInfo(Icons.auto_stories_rounded, Color(0xFF42A5F5));

    // ── Extension-based lookup ─────────────────────────────────────────────
    final ext = _ext(lower);
    return _extensionMap[ext] ?? const FileIconInfo(Icons.insert_drive_file_outlined, Color(0xFF8E8E8E));
  }

  /// Returns just the icon for a given filename.
  static IconData icon(String filename) => forFile(filename).icon;

  /// Returns just the colour for a given filename.
  static Color color(String filename) => forFile(filename).color;

  static String _ext(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot == -1 || dot == filename.length - 1) return '';
    return filename.substring(dot);
  }

  /// Returns the highlight.js language identifier for syntax highlighting.
  static String? highlightLanguage(String filename) {
    final lower = filename.toLowerCase();
    if (lower == 'dockerfile') return 'dockerfile';
    if (lower == 'makefile') return 'makefile';
    final ext = _ext(lower);
    return _highlightMap[ext];
  }

  // ── Extension → icon/colour table ────────────────────────────────────────

  static const Map<String, FileIconInfo> _extensionMap = {
    // ── Dart / Flutter ──────────────────────────────────────────────────
    '.dart': FileIconInfo(Icons.flutter_dash, Color(0xFF02569B)),

    // ── JavaScript ecosystem ────────────────────────────────────────────
    '.js':   FileIconInfo(Icons.javascript_rounded, Color(0xFFF7DF1E)),
    '.mjs':  FileIconInfo(Icons.javascript_rounded, Color(0xFFF7DF1E)),
    '.cjs':  FileIconInfo(Icons.javascript_rounded, Color(0xFFF7DF1E)),
    '.jsx':  FileIconInfo(Icons.code_rounded, Color(0xFF61DAFB)),
    '.ts':   FileIconInfo(Icons.code_rounded, Color(0xFF3178C6)),
    '.tsx':  FileIconInfo(Icons.code_rounded, Color(0xFF3178C6)),

    // ── Web ─────────────────────────────────────────────────────────────
    '.html': FileIconInfo(Icons.html_rounded, Color(0xFFE44D26)),
    '.htm':  FileIconInfo(Icons.html_rounded, Color(0xFFE44D26)),
    '.css':  FileIconInfo(Icons.css_rounded, Color(0xFF1572B6)),
    '.scss': FileIconInfo(Icons.css_rounded, Color(0xFFCD6799)),
    '.sass': FileIconInfo(Icons.css_rounded, Color(0xFFCD6799)),
    '.less': FileIconInfo(Icons.css_rounded, Color(0xFF1D365D)),
    '.vue':  FileIconInfo(Icons.change_history_rounded, Color(0xFF42B883)),
    '.svelte': FileIconInfo(Icons.whatshot_rounded, Color(0xFFFF3E00)),

    // ── Python ──────────────────────────────────────────────────────────
    '.py':   FileIconInfo(Icons.data_object_rounded, Color(0xFF3572A5)),
    '.pyw':  FileIconInfo(Icons.data_object_rounded, Color(0xFF3572A5)),
    '.pyi':  FileIconInfo(Icons.data_object_rounded, Color(0xFF3572A5)),
    '.ipynb': FileIconInfo(Icons.science_rounded, Color(0xFFF37626)),

    // ── Java / Kotlin / Scala ───────────────────────────────────────────
    '.java':  FileIconInfo(Icons.coffee_rounded, Color(0xFFB07219)),
    '.kt':    FileIconInfo(Icons.diamond_rounded, Color(0xFFA97BFF)),
    '.kts':   FileIconInfo(Icons.diamond_rounded, Color(0xFFA97BFF)),
    '.scala': FileIconInfo(Icons.whatshot_rounded, Color(0xFFDC322F)),
    '.groovy': FileIconInfo(Icons.code_rounded, Color(0xFF4298B8)),
    '.gradle': FileIconInfo(Icons.build_rounded, Color(0xFF02303A)),

    // ── C / C++ / C# ───────────────────────────────────────────────────
    '.c':    FileIconInfo(Icons.memory_rounded, Color(0xFF555555)),
    '.h':    FileIconInfo(Icons.memory_rounded, Color(0xFF9C27B0)),
    '.cpp':  FileIconInfo(Icons.memory_rounded, Color(0xFF00599C)),
    '.cc':   FileIconInfo(Icons.memory_rounded, Color(0xFF00599C)),
    '.cxx':  FileIconInfo(Icons.memory_rounded, Color(0xFF00599C)),
    '.hpp':  FileIconInfo(Icons.memory_rounded, Color(0xFF9C27B0)),
    '.hh':   FileIconInfo(Icons.memory_rounded, Color(0xFF9C27B0)),
    '.cs':   FileIconInfo(Icons.code_rounded, Color(0xFF178600)),
    '.asm':  FileIconInfo(Icons.developer_board_rounded, Color(0xFF6E4C13)),

    // ── Go / Rust ───────────────────────────────────────────────────────
    '.go':   FileIconInfo(Icons.directions_run_rounded, Color(0xFF00ADD8)),
    '.rs':   FileIconInfo(Icons.settings_rounded, Color(0xFFDEA584)),

    // ── Ruby / PHP / Perl ───────────────────────────────────────────────
    '.rb':   FileIconInfo(Icons.diamond_rounded, Color(0xFFCC342D)),
    '.php':  FileIconInfo(Icons.code_rounded, Color(0xFF777BB4)),
    '.pl':   FileIconInfo(Icons.code_rounded, Color(0xFF0298C3)),

    // ── Swift / Objective-C ─────────────────────────────────────────────
    '.swift': FileIconInfo(Icons.speed_rounded, Color(0xFFFA7343)),
    '.m':     FileIconInfo(Icons.code_rounded, Color(0xFF438EFF)),

    // ── Shell ───────────────────────────────────────────────────────────
    '.sh':   FileIconInfo(Icons.terminal_rounded, Color(0xFF4EAA25)),
    '.bash': FileIconInfo(Icons.terminal_rounded, Color(0xFF4EAA25)),
    '.zsh':  FileIconInfo(Icons.terminal_rounded, Color(0xFF4EAA25)),
    '.fish': FileIconInfo(Icons.terminal_rounded, Color(0xFF4EAA25)),
    '.ps1':  FileIconInfo(Icons.terminal_rounded, Color(0xFF012456)),
    '.bat':  FileIconInfo(Icons.terminal_rounded, Color(0xFF4D6B38)),
    '.cmd':  FileIconInfo(Icons.terminal_rounded, Color(0xFF4D6B38)),

    // ── Data / Config ───────────────────────────────────────────────────
    '.json':  FileIconInfo(Icons.data_object_rounded, Color(0xFFCBCB41)),
    '.jsonc': FileIconInfo(Icons.data_object_rounded, Color(0xFFCBCB41)),
    '.yaml':  FileIconInfo(Icons.tune_rounded, Color(0xFFE37933)),
    '.yml':   FileIconInfo(Icons.tune_rounded, Color(0xFFE37933)),
    '.xml':   FileIconInfo(Icons.code_rounded, Color(0xFFE37933)),
    '.toml':  FileIconInfo(Icons.tune_rounded, Color(0xFF9C4221)),
    '.ini':   FileIconInfo(Icons.settings_rounded, Color(0xFF8E8E8E)),
    '.cfg':   FileIconInfo(Icons.settings_rounded, Color(0xFF8E8E8E)),
    '.csv':   FileIconInfo(Icons.table_chart_rounded, Color(0xFF4CAF50)),
    '.sql':   FileIconInfo(Icons.storage_rounded, Color(0xFFE38C00)),
    '.graphql': FileIconInfo(Icons.hub_rounded, Color(0xFFE535AB)),
    '.proto':   FileIconInfo(Icons.schema_rounded, Color(0xFF4285F4)),
    '.env':   FileIconInfo(Icons.key_rounded, Color(0xFFFFC107)),

    // ── Docs / Text ─────────────────────────────────────────────────────
    '.md':    FileIconInfo(Icons.description_outlined, Color(0xFF42A5F5)),
    '.mdx':   FileIconInfo(Icons.description_outlined, Color(0xFF42A5F5)),
    '.txt':   FileIconInfo(Icons.text_snippet_outlined, Color(0xFF8E8E8E)),
    '.rst':   FileIconInfo(Icons.article_outlined, Color(0xFF8E8E8E)),
    '.pdf':   FileIconInfo(Icons.picture_as_pdf_rounded, Color(0xFFE53935)),
    '.tex':   FileIconInfo(Icons.functions_rounded, Color(0xFF008080)),
    '.log':   FileIconInfo(Icons.receipt_long_rounded, Color(0xFF8E8E8E)),

    // ── Media / Images ──────────────────────────────────────────────────
    '.png':  FileIconInfo(Icons.image_rounded, Color(0xFF26A69A)),
    '.jpg':  FileIconInfo(Icons.image_rounded, Color(0xFF26A69A)),
    '.jpeg': FileIconInfo(Icons.image_rounded, Color(0xFF26A69A)),
    '.gif':  FileIconInfo(Icons.gif_rounded, Color(0xFF26A69A)),
    '.svg':  FileIconInfo(Icons.draw_rounded, Color(0xFFFFB13B)),
    '.ico':  FileIconInfo(Icons.image_rounded, Color(0xFF26A69A)),
    '.webp': FileIconInfo(Icons.image_rounded, Color(0xFF26A69A)),
    '.mp4':  FileIconInfo(Icons.movie_rounded, Color(0xFFAB47BC)),
    '.webm': FileIconInfo(Icons.movie_rounded, Color(0xFFAB47BC)),
    '.mp3':  FileIconInfo(Icons.audiotrack_rounded, Color(0xFFFF7043)),
    '.wav':  FileIconInfo(Icons.audiotrack_rounded, Color(0xFFFF7043)),
    '.ogg':  FileIconInfo(Icons.audiotrack_rounded, Color(0xFFFF7043)),
    '.ttf':  FileIconInfo(Icons.font_download_rounded, Color(0xFFFF5252)),
    '.otf':  FileIconInfo(Icons.font_download_rounded, Color(0xFFFF5252)),
    '.woff': FileIconInfo(Icons.font_download_rounded, Color(0xFFFF5252)),
    '.woff2': FileIconInfo(Icons.font_download_rounded, Color(0xFFFF5252)),

    // ── Lock / Package ──────────────────────────────────────────────────
    '.lock': FileIconInfo(Icons.lock_outlined, Color(0xFF8E8E8E)),

    // ── Other ───────────────────────────────────────────────────────────
    '.r':    FileIconInfo(Icons.bar_chart_rounded, Color(0xFF276DC3)),
    '.lua':  FileIconInfo(Icons.nightlight_rounded, Color(0xFF000080)),
    '.ex':   FileIconInfo(Icons.water_drop_rounded, Color(0xFF6E4A7E)),
    '.exs':  FileIconInfo(Icons.water_drop_rounded, Color(0xFF6E4A7E)),
    '.erl':  FileIconInfo(Icons.code_rounded, Color(0xFFA90533)),
    '.zig':  FileIconInfo(Icons.bolt_rounded, Color(0xFFF7A41D)),
    '.wasm': FileIconInfo(Icons.memory_rounded, Color(0xFF654FF0)),
  };

  // ── Extension → highlight.js language identifier ─────────────────────────

  static const Map<String, String> _highlightMap = {
    '.dart':   'dart',
    '.js':     'javascript',
    '.mjs':    'javascript',
    '.cjs':    'javascript',
    '.jsx':    'javascript',
    '.ts':     'typescript',
    '.tsx':    'typescript',
    '.html':   'xml',
    '.htm':    'xml',
    '.css':    'css',
    '.scss':   'scss',
    '.sass':   'scss',
    '.less':   'less',
    '.py':     'python',
    '.pyw':    'python',
    '.java':   'java',
    '.kt':     'kotlin',
    '.kts':    'kotlin',
    '.scala':  'scala',
    '.groovy': 'groovy',
    '.c':      'c',
    '.h':      'c',
    '.cpp':    'cpp',
    '.cc':     'cpp',
    '.cxx':    'cpp',
    '.hpp':    'cpp',
    '.hh':     'cpp',
    '.cs':     'csharp',
    '.go':     'go',
    '.rs':     'rust',
    '.rb':     'ruby',
    '.php':    'php',
    '.swift':  'swift',
    '.m':      'objectivec',
    '.sh':     'bash',
    '.bash':   'bash',
    '.zsh':    'bash',
    '.ps1':    'powershell',
    '.bat':    'dos',
    '.cmd':    'dos',
    '.json':   'json',
    '.yaml':   'yaml',
    '.yml':    'yaml',
    '.xml':    'xml',
    '.toml':   'ini',
    '.sql':    'sql',
    '.md':     'markdown',
    '.mdx':    'markdown',
    '.tex':    'latex',
    '.r':      'r',
    '.lua':    'lua',
    '.ex':     'elixir',
    '.exs':    'elixir',
    '.erl':    'erlang',
    '.pl':     'perl',
    '.gradle': 'groovy',
    '.graphql': 'graphql',
  };
}
