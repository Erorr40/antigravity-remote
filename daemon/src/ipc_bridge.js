const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawn } = require('child_process');

class IpcBridge {
  constructor(antigravityAppData) {
    this.appData = antigravityAppData;
    this.ipcDir = path.join(this.appData, 'remote_ipc');
    this.activeProcesses = new Map(); // taskId -> ChildProcess
    this.ensureDirectories();
  }

  ensureDirectories() {
    if (!fs.existsSync(this.ipcDir)) {
      try {
        fs.mkdirSync(this.ipcDir, { recursive: true });
      } catch (err) {
        console.warn('[IPC] Could not create remote_ipc dir:', err.message);
      }
    }
  }

  /**
   * Inject user prompt into active session or queue
   */
  async dispatchPrompt({ sessionId, prompt, createNewSession, model }) {
    console.log(`[IPC] Dispatching prompt to session=${sessionId || 'new'}, model=${model || 'default'}`);

    const promptPayload = {
      id: `prompt-${Date.now()}`,
      timestamp: Date.now(),
      sessionId: sessionId || null,
      prompt,
      createNewSession: !!createNewSession,
      model: model || null
    };

    // 1. Write to incoming prompt queue file for Antigravity session
    const queueFile = path.join(this.ipcDir, `inbox_${sessionId || 'root'}.json`);
    fs.writeFileSync(queueFile, JSON.stringify(promptPayload, null, 2), 'utf8');

    // 2. Also record in session scratch/inbox if session exists
    if (sessionId) {
      const sessionInboxDir = path.join(this.appData, 'brain', sessionId, 'remote_inbox');
      try {
        if (!fs.existsSync(sessionInboxDir)) {
          fs.mkdirSync(sessionInboxDir, { recursive: true });
        }
        const sessionInboxFile = path.join(sessionInboxDir, `req_${Date.now()}.json`);
        fs.writeFileSync(sessionInboxFile, JSON.stringify(promptPayload, null, 2), 'utf8');
      } catch (err) {
        console.warn(`[IPC] Session inbox write warning:`, err.message);
      }
    }

    return {
      success: true,
      message: `Prompt queued successfully for session ${sessionId || 'new'}`,
      timestamp: Date.now()
    };
  }

  /**
   * Handle interactive tool input or question response
   */
  async handleToolInput({ sessionId, callId, action, inputText }) {
    console.log(`[IPC] Tool input received: callId=${callId}, action=${action}`);

    const responsePayload = {
      callId,
      action, // 'approve', 'reject', 'send_input'
      inputText: inputText || '',
      timestamp: Date.now()
    };

    const responseFile = path.join(this.ipcDir, `tool_resp_${callId || sessionId}.json`);
    fs.writeFileSync(responseFile, JSON.stringify(responsePayload, null, 2), 'utf8');

    return {
      success: true,
      message: `Tool action '${action}' registered for call ${callId}`,
      timestamp: Date.now()
    };
  }

  /**
   * Remote abort signal to cancel running subagents or tasks
   */
  async abortTask({ sessionId, taskId, reason }) {
    console.log(`[IPC] Remote abort requested for session=${sessionId}, task=${taskId || 'all'}, reason=${reason}`);

    const abortSignalFile = path.join(this.ipcDir, `abort_${sessionId}.json`);
    fs.writeFileSync(abortSignalFile, JSON.stringify({
      sessionId,
      taskId: taskId || null,
      reason: reason || 'Remote user requested cancellation',
      timestamp: Date.now()
    }, null, 2), 'utf8');

    // Kill tracked child process if active
    if (taskId && this.activeProcesses.has(taskId)) {
      const proc = this.activeProcesses.get(taskId);
      try {
        proc.kill('SIGTERM');
        this.activeProcesses.delete(taskId);
      } catch (err) {
        console.warn(`[IPC] Error killing process ${taskId}:`, err.message);
      }
    }

    return {
      success: true,
      message: `Abort signal dispatched to task ${taskId || 'all'} in session ${sessionId}`,
      timestamp: Date.now()
    };
  }
}

module.exports = {
  IpcBridge
};
