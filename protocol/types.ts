/**
 * Antigravity Remote Protocol TypeScript Type Definitions
 * Shared contract for Daemon, Relay, and Clients
 */

export type MessageType =
  | 'HEARTBEAT_PING'
  | 'HEARTBEAT_PONG'
  | 'PAIRING_REQUEST'
  | 'PAIRING_RESPONSE'
  | 'KEY_EXCHANGE_INIT'
  | 'KEY_EXCHANGE_ACK'
  | 'ENCRYPTED_CONTAINER'
  | 'RELAY_ERROR';

export interface EncryptedPayload {
  senderKeyId: string;
  nonce: string; // Base64 12 bytes AES-GCM IV or 24 bytes XChaCha20
  ciphertext: string; // Base64 ciphertext + tag
  sequenceNumber: number;
}

export interface RelayEnvelope<T = any> {
  messageId: string;
  timestamp: number;
  type: MessageType;
  senderId: string;
  targetId: string;
  plainPayload?: T;
  encryptedPayload?: EncryptedPayload;
}

export interface PairingQrData {
  v: 1;
  relayUrl: string;
  hostDeviceId: string;
  hostName: string;
  hostPublicKey: string; // Base64 Curve25519
  pairToken: string;
  expiresAt: number;
}

export interface PairingRequest {
  pairToken: string;
  mobileDeviceId: string;
  deviceName: string;
  mobilePublicKey: string; // Base64 Curve25519
}

export interface PairingResponse {
  success: boolean;
  hostDeviceId: string;
  hostPublicKey: string;
  salt?: string;
  errorMessage?: string;
}

export interface HostHeartbeat {
  online: boolean;
  hostOs: string;
  activeSessionId: string | null;
  activeTasksCount: number;
  hostVersion: string;
  uptimeSeconds: number;
  memoryUsagePercent?: number;
}

export type InnerActionType =
  | 'REQ_SESSION_LIST'
  | 'RESP_SESSION_LIST'
  | 'REQ_TRANSCRIPT_SYNC'
  | 'RESP_TRANSCRIPT_SNAPSHOT'
  | 'EVT_TRANSCRIPT_DELTA'
  | 'CMD_DISPATCH_PROMPT'
  | 'CMD_ABORT_TASK'
  | 'CMD_SEND_TOOL_INPUT'
  | 'RESP_COMMAND_ACK'
  | 'REQ_ARTIFACT_LIST'
  | 'RESP_ARTIFACT_LIST'
  | 'REQ_ARTIFACT_CONTENT'
  | 'RESP_ARTIFACT_CONTENT';

export interface InnerMessage<T = any> {
  innerId: string;
  timestamp: number;
  action: InnerActionType;
  sessionId?: string;
  payload: T;
}

export interface SessionSummary {
  sessionId: string;
  projectDir: string;
  createdAtMs: number;
  updatedAtMs: number;
  totalSteps: number;
  lastUserPrompt?: string;
  lastAgentStatus: 'idle' | 'thinking' | 'tool_executing' | 'waiting_for_input' | 'done' | 'error';
  hasActiveTask: boolean;
}

export interface ToolCall {
  tool_name: string;
  tool_action?: string;
  tool_summary?: string;
  call_id?: string;
  arguments?: Record<string, any>;
  result?: any;
  is_error?: boolean;
}

export interface TranscriptStep {
  step_index: number;
  source: 'USER_EXPLICIT' | 'MODEL' | 'SYSTEM';
  type: 'USER_INPUT' | 'PLANNER_RESPONSE' | 'TOOL_RESULT' | string;
  status: 'DONE' | 'ERROR' | 'RUNNING' | string;
  created_at: string;
  content?: string;
  thinking?: string;
  tool_calls?: ToolCall[];
  media?: Array<{ mime_type: string; uri: string }>;
  truncated_fields?: string[];
}

export type DeltaKind = 'APPEND_STEP' | 'UPDATE_STEP' | 'STREAM_THINKING' | 'STREAM_CONTENT';

export interface TranscriptDeltaEvent {
  sessionId: string;
  kind: DeltaKind;
  stepIndex: number;
  textChunk?: string;
  step?: TranscriptStep;
}

export interface DispatchPromptPayload {
  sessionId?: string;
  prompt: string;
  createNewSession?: boolean;
  model?: string;
}

export interface AbortTaskPayload {
  sessionId: string;
  taskId?: string;
  reason?: string;
}

export interface ToolInputPayload {
  sessionId: string;
  callId: string;
  action: 'approve' | 'reject' | 'send_input';
  inputText?: string;
}

export interface ArtifactItem {
  fileName: string;
  filePath: string;
  sizeBytes: number;
  modifiedAt: number;
  mimeType: string;
}
