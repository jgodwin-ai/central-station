import { createServer, type Server, type IncomingMessage, type ServerResponse } from "node:http";
import { EventEmitter } from "node:events";
import type { StopHookPayload } from "../types.js";

export interface HookEvent {
  sessionId: string;
  lastMessage: string;
}

export class HookServer extends EventEmitter {
  private server: Server;
  private _port = 0;

  constructor() {
    super();
    this.server = createServer((req, res) => this.handleRequest(req, res));
  }

  get port(): number {
    return this._port;
  }

  async start(): Promise<number> {
    return new Promise((resolve, reject) => {
      this.server.listen(0, "127.0.0.1", () => {
        const addr = this.server.address();
        if (addr && typeof addr === "object") {
          this._port = addr.port;
          resolve(this._port);
        } else {
          reject(new Error("Failed to get server address"));
        }
      });
      this.server.on("error", reject);
    });
  }

  async stop(): Promise<void> {
    return new Promise((resolve) => {
      this.server.close(() => resolve());
    });
  }

  private handleRequest(req: IncomingMessage, res: ServerResponse): void {
    if (req.method !== "POST" || req.url !== "/hook/stop") {
      res.writeHead(404);
      res.end();
      return;
    }

    let body = "";
    req.on("data", (chunk: Buffer) => {
      body += chunk.toString();
    });

    req.on("end", () => {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end("{}");

      try {
        const payload = JSON.parse(body) as StopHookPayload;

        if (payload.stop_hook_active) {
          return;
        }

        if (payload.hook_event_name === "Stop" && payload.session_id) {
          this.emit("stop", {
            sessionId: payload.session_id,
            lastMessage: payload.last_assistant_message || "",
          } satisfies HookEvent);
        }
      } catch {
        // Ignore malformed payloads
      }
    });
  }
}
