'use strict';
// ─────────────────────────────────────────────────────────────────────────────
// file_index.js
//
// Lightweight in-process file index rebuilt whenever the workspace changes.
// No external dependencies — walks the tree with Node's fs module.
// ─────────────────────────────────────────────────────────────────────────────

const fs   = require('fs');
const path = require('path');

// Directories and extensions that are never indexed
const SKIP_DIRS = new Set([
  '.git', 'node_modules', '.dart_tool', 'build', '.build',
  'dist', 'out', '.cache', '__pycache__', '.venv', 'venv',
  'Pods', 'DerivedData', '.gradle',
]);
const SKIP_EXTS = new Set([
  '.png', '.jpg', '.jpeg', '.gif', '.ico', '.svg', '.webp', '.bmp',
  '.mp4', '.mp3', '.mov', '.avi', '.wav',
  '.zip', '.tar', '.gz', '.rar', '.7z',
  '.pdf', '.docx', '.xlsx',
  '.exe', '.dll', '.so', '.dylib', '.a',
  '.gguf', '.bin', '.safetensors',
]);

class FileIndex {
  constructor() {
    /** @type {Map<string, {path: string, mtime: number, size: number}>} */
    this._entries = new Map();
    this._workspaceRoot = '';
    this._building = false;
  }

  /** Asynchronously (re)build the index for a workspace root. */
  async rebuild(workspaceRoot) {
    if (this._building) return;
    this._building = true;
    this._workspaceRoot = workspaceRoot;
    this._entries.clear();

    try {
      await this._walk(workspaceRoot, workspaceRoot);
      console.log(`[FileIndex] Indexed ${this._entries.size} files in ${path.basename(workspaceRoot)}`);
    } finally {
      this._building = false;
    }
  }

  async _walk(dir, root) {
    let entries;
    try {
      entries = await fs.promises.readdir(dir, { withFileTypes: true });
    } catch {
      return;
    }

    for (const entry of entries) {
      if (entry.name.startsWith('.') && SKIP_DIRS.has(entry.name)) continue;
      if (SKIP_DIRS.has(entry.name)) continue;

      const abs = path.join(dir, entry.name);

      if (entry.isDirectory()) {
        await this._walk(abs, root);
      } else if (entry.isFile()) {
        const ext = path.extname(entry.name).toLowerCase();
        if (SKIP_EXTS.has(ext)) continue;
        try {
          const stat = await fs.promises.stat(abs);
          const rel  = path.relative(root, abs);
          this._entries.set(rel, { path: rel, mtime: stat.mtimeMs, size: stat.size });
        } catch { /* ignore unreadable files */ }
      }
    }
  }

  /**
   * Find files whose name (basename) matches `name` (case-insensitive).
   * @returns {Array<{path, mtime, size}>}
   */
  findByName(name) {
    const lower = name.toLowerCase();
    const results = [];
    for (const entry of this._entries.values()) {
      if (path.basename(entry.path).toLowerCase().includes(lower)) {
        results.push(entry);
      }
    }
    return results;
  }

  /**
   * Find files with a specific extension (e.g. '.dart', '.js').
   * @returns {Array<{path, mtime, size}>}
   */
  findByExtension(ext) {
    const lower = ext.toLowerCase().startsWith('.') ? ext.toLowerCase() : '.' + ext.toLowerCase();
    const results = [];
    for (const entry of this._entries.values()) {
      if (path.extname(entry.path).toLowerCase() === lower) {
        results.push(entry);
      }
    }
    return results;
  }

  /**
   * Return the N most recently modified files.
   * @returns {Array<{path, mtime, size}>}
   */
  getRecentlyModified(n = 10) {
    return Array.from(this._entries.values())
      .sort((a, b) => b.mtime - a.mtime)
      .slice(0, n);
  }

  /** Total indexed file count. */
  get size() { return this._entries.size; }
}

// Singleton instance shared across the server process
const fileIndex = new FileIndex();

module.exports = { fileIndex, FileIndex };
