const fs = require('fs');
const path = require('path');

class ArtifactsManager {
  constructor(brainDir) {
    this.brainDir = brainDir;
  }

  /**
   * List all artifact files in conversation directory
   */
  async listArtifacts(sessionId) {
    const sessionDir = path.join(this.brainDir, sessionId);
    if (!fs.existsSync(sessionDir)) {
      return [];
    }

    const artifacts = [];
    const walk = (currentDir, relativePath = '') => {
      let entries = [];
      try {
        entries = fs.readdirSync(currentDir, { withFileTypes: true });
      } catch {
        return;
      }

      for (const entry of entries) {
        if (entry.name.startsWith('.') || entry.name === 'node_modules') {
          continue;
        }

        const fullPath = path.join(currentDir, entry.name);
        const rel = path.join(relativePath, entry.name);

        if (entry.isDirectory()) {
          walk(fullPath, rel);
        } else if (entry.isFile()) {
          try {
            const stats = fs.statSync(fullPath);
            artifacts.push({
              fileName: entry.name,
              filePath: rel.replace(/\\/g, '/'),
              sizeBytes: stats.size,
              modifiedAt: Math.floor(stats.mtimeMs),
              mimeType: this.guessMimeType(entry.name)
            });
          } catch {}
        }
      }
    };

    walk(sessionDir);
    return artifacts;
  }

  /**
   * Get content of artifact file
   */
  async getArtifactContent(sessionId, relativeFilePath) {
    const sessionDir = path.join(this.brainDir, sessionId);
    const targetPath = path.resolve(sessionDir, relativeFilePath);

    // Prevent directory traversal attacks
    if (!targetPath.startsWith(path.resolve(sessionDir))) {
      throw new Error('Access denied: Path traversal detected');
    }

    if (!fs.existsSync(targetPath)) {
      throw new Error('Artifact not found: ' + relativeFilePath);
    }

    const mime = this.guessMimeType(targetPath);
    const isText = this.isTextFile(mime);

    if (isText) {
      const content = fs.readFileSync(targetPath, 'utf8');
      return {
        sessionId,
        fileName: path.basename(targetPath),
        mimeType: mime,
        isText: true,
        content
      };
    } else {
      const buffer = fs.readFileSync(targetPath);
      return {
        sessionId,
        fileName: path.basename(targetPath),
        mimeType: mime,
        isText: false,
        content: buffer.toString('base64')
      };
    }
  }

  guessMimeType(filename) {
    const ext = path.extname(filename).toLowerCase();
    switch (ext) {
      case '.md': return 'text/markdown';
      case '.txt': return 'text/plain';
      case '.json': return 'application/json';
      case '.js': return 'application/javascript';
      case '.ts': return 'text/typescript';
      case '.dart': return 'text/x-dart';
      case '.py': return 'text/x-python';
      case '.html': return 'text/html';
      case '.css': return 'text/css';
      case '.diff':
      case '.patch': return 'text/x-diff';
      case '.png': return 'image/png';
      case '.jpg':
      case '.jpeg': return 'image/jpeg';
      case '.svg': return 'image/svg+xml';
      default: return 'application/octet-stream';
    }
  }

  isTextFile(mime) {
    return mime.startsWith('text/') || mime === 'application/json' || mime === 'application/javascript';
  }
}

module.exports = {
  ArtifactsManager
};
