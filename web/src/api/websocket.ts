// ============================================================================
// WebSocket Client for Real-time Updates
// ============================================================================

type MessageHandler = (data: unknown) => void;
type ConnectionHandler = () => void;

export interface WebSocketMessage {
  type: string;
  channel?: string;
  data?: unknown;
  timestamp?: number;
}

export class ZigQuantWebSocket {
  private ws: WebSocket | null = null;
  private url: string;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 5;
  private reconnectDelay = 1000;
  private messageHandlers: Map<string, Set<MessageHandler>> = new Map();
  private connectionHandlers: {
    onOpen: Set<ConnectionHandler>;
    onClose: Set<ConnectionHandler>;
    onError: Set<(error: Event) => void>;
  } = {
    onOpen: new Set(),
    onClose: new Set(),
    onError: new Set(),
  };
  private subscriptions: Set<string> = new Set();
  private pingInterval: ReturnType<typeof setInterval> | null = null;

  constructor(url?: string) {
    this.url = url || import.meta.env.VITE_WS_URL || 'ws://localhost:8080/ws';
  }

  // ========================================================================
  // Connection Management
  // ========================================================================

  connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      if (this.ws?.readyState === WebSocket.OPEN) {
        resolve();
        return;
      }

      try {
        this.ws = new WebSocket(this.url);

        this.ws.onopen = () => {
          console.log('[WS] Connected to', this.url);
          this.reconnectAttempts = 0;
          this.connectionHandlers.onOpen.forEach(handler => handler());
          
          // Resubscribe to channels
          this.subscriptions.forEach(channel => {
            this.sendSubscribe(channel);
          });

          // Start ping interval
          this.startPing();
          
          resolve();
        };

        this.ws.onclose = () => {
          console.log('[WS] Disconnected');
          this.stopPing();
          this.connectionHandlers.onClose.forEach(handler => handler());
          this.attemptReconnect();
        };

        this.ws.onerror = (error) => {
          console.error('[WS] Error:', error);
          this.connectionHandlers.onError.forEach(handler => handler(error));
          reject(error);
        };

        this.ws.onmessage = (event) => {
          this.handleMessage(event.data);
        };
      } catch (error) {
        reject(error);
      }
    });
  }

  disconnect() {
    this.stopPing();
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
  }

  private attemptReconnect() {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error('[WS] Max reconnect attempts reached');
      return;
    }

    this.reconnectAttempts++;
    const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1);
    
    console.log(`[WS] Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts})`);
    
    setTimeout(() => {
      this.connect().catch(() => {});
    }, delay);
  }

  private startPing() {
    this.pingInterval = setInterval(() => {
      if (this.ws?.readyState === WebSocket.OPEN) {
        this.send({ type: 'ping' });
      }
    }, 30000);
  }

  private stopPing() {
    if (this.pingInterval) {
      clearInterval(this.pingInterval);
      this.pingInterval = null;
    }
  }

  // ========================================================================
  // Message Handling
  // ========================================================================

  private handleMessage(data: string) {
    try {
      const message: WebSocketMessage = JSON.parse(data);
      
      // Handle pong
      if (message.type === 'pong') {
        return;
      }

      // Dispatch to channel handlers
      if (message.channel) {
        const handlers = this.messageHandlers.get(message.channel);
        handlers?.forEach(handler => handler(message.data));

        // Also dispatch to wildcard handlers
        const wildcardHandlers = this.messageHandlers.get('*');
        wildcardHandlers?.forEach(handler => handler(message));
      }

      // Dispatch to type handlers
      const typeHandlers = this.messageHandlers.get(`type:${message.type}`);
      typeHandlers?.forEach(handler => handler(message));

    } catch (error) {
      console.error('[WS] Failed to parse message:', error);
    }
  }

  // ========================================================================
  // Subscriptions
  // ========================================================================

  subscribe(channel: string, handler: MessageHandler): () => void {
    // Add to handlers
    if (!this.messageHandlers.has(channel)) {
      this.messageHandlers.set(channel, new Set());
    }
    this.messageHandlers.get(channel)!.add(handler);

    // Add to subscriptions and send subscribe message
    if (!this.subscriptions.has(channel)) {
      this.subscriptions.add(channel);
      this.sendSubscribe(channel);
    }

    // Return unsubscribe function
    return () => {
      const handlers = this.messageHandlers.get(channel);
      if (handlers) {
        handlers.delete(handler);
        if (handlers.size === 0) {
          this.messageHandlers.delete(channel);
          this.subscriptions.delete(channel);
          this.sendUnsubscribe(channel);
        }
      }
    };
  }

  private sendSubscribe(channel: string) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.send({ type: 'subscribe', channel });
    }
  }

  private sendUnsubscribe(channel: string) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.send({ type: 'unsubscribe', channel });
    }
  }

  // ========================================================================
  // Event Handlers
  // ========================================================================

  onOpen(handler: ConnectionHandler): () => void {
    this.connectionHandlers.onOpen.add(handler);
    return () => this.connectionHandlers.onOpen.delete(handler);
  }

  onClose(handler: ConnectionHandler): () => void {
    this.connectionHandlers.onClose.add(handler);
    return () => this.connectionHandlers.onClose.delete(handler);
  }

  onError(handler: (error: Event) => void): () => void {
    this.connectionHandlers.onError.add(handler);
    return () => this.connectionHandlers.onError.delete(handler);
  }

  onMessage(type: string, handler: MessageHandler): () => void {
    const key = `type:${type}`;
    if (!this.messageHandlers.has(key)) {
      this.messageHandlers.set(key, new Set());
    }
    this.messageHandlers.get(key)!.add(handler);
    return () => {
      const handlers = this.messageHandlers.get(key);
      handlers?.delete(handler);
    };
  }

  // ========================================================================
  // Commands
  // ========================================================================

  send(message: WebSocketMessage) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message));
    }
  }

  // Strategy commands
  startStrategy(id: string, request: Record<string, unknown>) {
    this.send({
      type: 'strategy.start',
      data: { id, ...request },
    });
  }

  stopStrategy(id: string) {
    this.send({
      type: 'strategy.stop',
      data: { id },
    });
  }

  pauseStrategy(id: string) {
    this.send({
      type: 'strategy.pause',
      data: { id },
    });
  }

  resumeStrategy(id: string) {
    this.send({
      type: 'strategy.resume',
      data: { id },
    });
  }

  // Kill switch
  activateKillSwitch(reason: string) {
    this.send({
      type: 'system.kill_switch',
      data: { action: 'activate', reason },
    });
  }

  // ========================================================================
  // Status
  // ========================================================================

  get isConnected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }

  get readyState(): number {
    return this.ws?.readyState ?? WebSocket.CLOSED;
  }
}

// Singleton instance
export const wsClient = new ZigQuantWebSocket();

export default wsClient;
