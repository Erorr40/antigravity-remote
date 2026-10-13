const fs = require('fs');
const path = require('path');
const EventEmitter = require('events');

class TranscriptWatcher extends EventEmitter {
  constructor(brainDir) {
    super();
    this.brainDir = brainDir;
    this.sessionOffsets = new Map(); // sessionId -> file byte offset
    this.activeWatchers = new Map(); // sessionId -> fs.FSWatcher
    this.currentLiveSessionId = null;
    this.pollInterval = null;
  }

  /**
   * List all conversation sessions with metadata
   */
  async listSessions(limit = 30) {
    if (!fs.existsSync(this.brainDir)) {
      return [];
    }

    const entries = fs.readdirSync(this.brainDir, { withFileTypes: true });
    const sessionDirs = entries.filter(e => e.isDirectory() && e.name !== 'tempmediaStorage');

    const sessions = [];

    for (const dir of sessionDirs) {
      const sessionId = dir.name;
      const sessionPath = path.join(this.brainDir, sessionId);
      const logDir = path.join(sessionPath, '.system_generated', 'logs');
      const transcriptFile = path.join(logDir, 'transcript.jsonl');

      let stats = null;
      try {
        stats = fs.statSync(sessionPath);
      } catch {
        continue;
      }

      let totalSteps = 0;
      let lastUserPrompt = '';
      let lastAgentStatus = 'idle';
      let hasActiveTask = false;

      if (fs.existsSync(transcriptFile)) {
        try {
          const fileStats = fs.statSync(transcriptFile);
          // Read last few lines to deduce status and last prompt
          const recentContent = this.readTailLines(transcriptFile, 10);
          for (const line of recentContent) {
            if (!line.trim()) continue;
            try {
              const step = JSON.parse(line);
              totalSteps = Math.max(totalSteps, (step.step_index ?? 0) + 1);

              if (step.source === 'USER_EXPLICIT' && step.content) {
                // Strip tags for clean summary
                lastUserPrompt = step.content
                  .replace(/<USER_REQUEST>|<\/USER_REQUEST>/g, '')
                  .trim()
                  .slice(0, 150);
              }

              if (step.source === 'MODEL') {
                if (step.status === 'RUNNING') {
                  lastAgentStatus = step.thinking ? 'thinking' : 'tool_executing';
                  hasActiveTask = true;
                } else if (step.status === 'DONE') {
                  lastAgentStatus = 'done';
                } else if (step.status === 'ERROR') {
                  lastAgentStatus = 'error';
                }
              }
            } catch {
              // ignore malformed line
            }
          }

          // If file was modified in last 60 seconds, mark as live candidate
          if (Date.now() - fileStats.mtimeMs < 60000 && lastAgentStatus !== 'done') {
            hasActiveTask = true;
          }
        } catch (err) {
          console.warn(`[Watcher] Error reading ${transcriptFile}:`, err.message);
        }
      }

      sessions.push({
        sessionId,
        projectDir: sessionPath,
        createdAtMs: Math.floor(stats.birthtimeMs || stats.ctimeMs),
        updatedAtMs: Math.floor(stats.mtimeMs),
        totalSteps,
        lastUserPrompt: lastUserPrompt || '(New Session)',
        lastAgentStatus,
        hasActiveTask
      });
    }

    // Sort by most recently updated
    sessions.sort((a, b) => b.updatedAtMs - a.updatedAtMs);
    return sessions.slice(0, limit);
  }

  /**
   * Read full transcript snapshot for a given session
   */
  async getTranscriptSnapshot(sessionId, fromStep = 0) {
    const transcriptPath = path.join(this.brainDir, sessionId, '.system_generated', 'logs', 'transcript.jsonl');
    const fullLogPath = path.join(this.brainDir, sessionId, '.system_generated', 'logs', 'transcript_full.jsonl');

    if (!fs.existsSync(transcriptPath)) {
      return { sessionId, steps: [], isLive: false };
    }

    const steps = [];
    const content = fs.readFileSync(transcriptPath, 'utf8');
    const lines = content.split('\n');

    let fullLines = null;
    if (fs.existsSync(fullLogPath)) {
      try {
        fullLines = fs.readFileSync(fullLogPath, 'utf8').split('\n');
      } catch {
        fullLines = null;
      }
    }

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) continue;
      try {
        let step = JSON.parse(line);
        if (step.step_index < fromStep) continue;

        // If step content was truncated in compact log, resolve from full log if available
        if (step.truncated_fields && step.truncated_fields.length > 0 && fullLines && fullLines[i]) {
          try {
            const fullStep = JSON.parse(fullLines[i].trim());
            step = { ...step, ...fullStep };
          } catch {
            // keep compact step
          }
        }

        steps.push(step);
      } catch {
        // ignore malformed line
      }
    }

    const stats = fs.statSync(transcriptPath);
    const isLive = Date.now() - stats.mtimeMs < 60000;

    return {
      sessionId,
      steps,
      isLive
    };
  }

  /**
   * Start watching a specific session for live changes
   */
  watchSession(sessionId) {
    if (this.currentLiveSessionId === sessionId) {
      return;
    }

    this.stopWatching();
    this.currentLiveSessionId = sessionId;

    const transcriptPath = path.join(this.brainDir, sessionId, '.system_generated', 'logs', 'transcript.jsonl');
    if (!fs.existsSync(transcriptPath)) {
      return;
    }

    const stats = fs.statSync(transcriptPath);
    this.sessionOffsets.set(sessionId, stats.size);

    // File watcher for instant change notifications
    const watcher = fs.watch(transcriptPath, (eventType) => {
      if (eventType === 'change') {
        this.processNewBytes(sessionId, transcriptPath);
      }
    });

    this.activeWatchers.set(sessionId, watcher);

    // Fallback polling every 500ms for fast responsive streaming
    this.pollInterval = setInterval(() => {
      this.processNewBytes(sessionId, transcriptPath);
    }, 500);

    console.log(`[Watcher] Started monitoring session: ${sessionId}`);
  }

  stopWatching() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }

    for (const [id, watcher] of this.activeWatchers.entries()) {
      try {
        watcher.close();
      } catch {}
    }
    this.activeWatchers.clear();
    this.currentLiveSessionId = null;
  }

  /**
   * Process appended bytes since last offset
   */
  processNewBytes(sessionId, filePath) {
    let currentSize = 0;
    try {
      currentSize = fs.statSync(filePath).size;
    } catch {
      return;
    }

    const prevOffset = this.sessionOffsets.get(sessionId) || 0;
    if (currentSize <= prevOffset) {
      return;
    }

    const bytesToRead = currentSize - prevOffset;
    const buffer = Buffer.alloc(bytesToRead);
    let fd = null;

    try {
      fd = fs.openSync(filePath, 'r');
      fs.readSync(fd, buffer, 0, bytesToRead, prevOffset);
      this.sessionOffsets.set(sessionId, currentSize);
    } catch (err) {
      console.warn(`[Watcher] Error reading appended bytes from ${filePath}:`, err.message);
      return;
    } finally {
      if (fd !== null) {
        try { fs.closeSync(fd); } catch {}
      }
    }

    const appendedText = buffer.toString('utf8');
    const lines = appendedText.split('\n');

    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const step = JSON.parse(line.trim());
        this.emit('transcript_delta', {
          sessionId,
          kind: 'APPEND_STEP',
          stepIndex: step.step_index,
          step
        });
      } catch {
        // If incomplete line streaming in progress, emit as partial text chunk
        if (line.length > 0) {
          this.emit('transcript_delta', {
            sessionId,
            kind: 'STREAM_CONTENT',
            stepIndex: -1,
            textChunk: line
          });
        }
      }
    }
  }

  readTailLines(filePath, maxLines = 10) {
    try {
      const content = fs.readFileSync(filePath, 'utf8');
      const lines = content.split('\n').filter(l => l.trim().length > 0);
      return lines.slice(-maxLines);
    } catch {
      return [];
    }
  }
}

module.exports = {
  TranscriptWatcher
};
