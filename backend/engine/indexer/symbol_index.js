'use strict';
// ─────────────────────────────────────────────────────────────────────────────
// symbol_index.js
//
// Regex-based symbol extractor. Builds a searchable map of
// function / class / method definitions from source files.
// Supports: JavaScript, TypeScript, Dart, Python, Go, Rust, Swift, Kotlin.
// No LSP or tree-sitter dependency required.
// ─────────────────────────────────────────────────────────────────────────────

const fs   = require('fs');
const path = require('path');
const { fileIndex } = require('./file_index');

// Per-language extraction patterns
// Each pattern must have a capture group (1) for the symbol name.
const LANG_PATTERNS = {
  '.js':   [/^(?:export\s+)?(?:async\s+)?function\s+(\w+)/gm, /^\s*(?:async\s+)?(\w+)\s*\([^)]*\)\s*\{/gm, /^(?:export\s+)?class\s+(\w+)/gm],
  '.ts':   [/^(?:export\s+)?(?:async\s+)?function\s+(\w+)/gm, /^\s*(?:public|private|protected|async|static|\s)*(\w+)\s*\([^)]*\)\s*(?::\s*\S+)?\s*\{/gm, /^(?:export\s+)?(?:abstract\s+)?class\s+(\w+)/gm, /^(?:export\s+)?interface\s+(\w+)/gm],
  '.dart': [/^\s*(?:Future<[^>]+>|void|String|int|bool|double|List|Map|Widget|[A-Z]\w+)\s+(\w+)\s*\(/gm, /^(?:abstract\s+)?class\s+(\w+)/gm, /^\s*enum\s+(\w+)/gm],
  '.py':   [/^(?:async\s+)?def\s+(\w+)/gm, /^class\s+(\w+)/gm],
  '.go':   [/^func\s+(?:\(\w+\s+\*?\w+\)\s+)?(\w+)/gm, /^type\s+(\w+)\s+struct/gm, /^type\s+(\w+)\s+interface/gm],
  '.rs':   [/^(?:pub\s+)?(?:async\s+)?fn\s+(\w+)/gm, /^(?:pub\s+)?struct\s+(\w+)/gm, /^(?:pub\s+)?enum\s+(\w+)/gm, /^(?:pub\s+)?trait\s+(\w+)/gm],
  '.swift':[/^(?:open\s+|public\s+|internal\s+|private\s+)?(?:final\s+)?(?:class|struct|enum|protocol)\s+(\w+)/gm, /^\s*(?:open\s+|public\s+|internal\s+|private\s+)?(?:override\s+)?(?:static\s+)?func\s+(\w+)/gm],
  '.kt':   [/^(?:fun)\s+(\w+)/gm, /^(?:class|object|interface|data class)\s+(\w+)/gm],
};

// Determine kind string from pattern index
function kindFor(ext, patternIdx) {
  switch (ext) {
    case '.py':   return patternIdx === 0 ? 'function' : 'class';
    case '.go':   return patternIdx === 0 ? 'function' : 'struct';
    case '.rs':   return ['function', 'struct', 'enum', 'trait'][patternIdx] || 'symbol';
    case '.dart': return patternIdx === 0 ? 'function' : patternIdx === 1 ? 'class' : 'enum';
    default:      return patternIdx === 0 ? 'function' : 'class';
  }
}

class SymbolIndex {
  constructor() {
    /** @type {Map<string, Array<{name, kind, file, line}>>} */
    this._byName = new Map();
    this._building = false;
  }

  /** Rebuild the symbol index for all indexed source files. */
  async rebuild(workspaceRoot) {
    if (this._building) return;
    this._building = true;
    this._byName.clear();

    const exts = Object.keys(LANG_PATTERNS);
    let total = 0;

    try {
      for (const ext of exts) {
        const files = fileIndex.findByExtension(ext);
        for (const entry of files) {
          await this._indexFile(workspaceRoot, entry.path, ext);
          total++;
        }
      }
      console.log(`[SymbolIndex] Indexed ${this._byName.size} unique symbols across ${total} files`);
    } finally {
      this._building = false;
    }
  }

  async _indexFile(workspaceRoot, relPath, ext) {
    const abs = path.join(workspaceRoot, relPath);
    let src;
    try {
      src = await fs.promises.readFile(abs, 'utf8');
    } catch {
      return;
    }

    const patterns = LANG_PATTERNS[ext] || [];
    const lines    = src.split('\n');

    for (let pi = 0; pi < patterns.length; pi++) {
      const re = new RegExp(patterns[pi].source, patterns[pi].flags);
      let match;
      while ((match = re.exec(src)) !== null) {
        const name = match[1];
        if (!name || name.length < 2) continue;

        // Determine line number
        const before = src.slice(0, match.index);
        const line   = before.split('\n').length;

        const entry = { name, kind: kindFor(ext, pi), file: relPath, line };
        if (!this._byName.has(name)) this._byName.set(name, []);
        this._byName.get(name).push(entry);
      }
    }
  }

  /**
   * Find all occurrences of a symbol by exact or partial name match.
   * @param {string} name
   * @returns {Array<{name, kind, file, line}>}
   */
  findSymbol(name) {
    const lower = name.toLowerCase();
    const results = [];
    for (const [key, entries] of this._byName) {
      if (key.toLowerCase().includes(lower)) {
        results.push(...entries);
      }
    }
    return results.slice(0, 20);   // Cap results
  }

  /** All indexed symbol names. */
  get symbolCount() { return this._byName.size; }
}

const symbolIndex = new SymbolIndex();
module.exports = { symbolIndex, SymbolIndex };
