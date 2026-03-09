import { describe, it, afterEach } from "node:test";
import assert from "node:assert/strict";
import { HookServer, type HookEvent } from "../hook-server.js";

let server: HookServer | null = null;

afterEach(async () => {
  if (server) {
    await server.stop();
    server = null;
  }
});

describe("HookServer", () => {
  it("starts on a random port", async () => {
    server = new HookServer();
    const port = await server.start();
    assert.ok(port > 0);
    assert.equal(server.port, port);
  });

  it("emits stop event on valid Stop hook payload", async () => {
    server = new HookServer();
    const port = await server.start();

    const received = new Promise<HookEvent>((resolve) => {
      server!.on("stop", resolve);
    });

    const payload = {
      session_id: "abc-123",
      transcript_path: "/tmp/transcript.jsonl",
      cwd: "/tmp",
      permission_mode: "default",
      hook_event_name: "Stop",
      stop_hook_active: false,
      last_assistant_message: "I'm done, what's next?",
    };

    const res = await fetch(`http://127.0.0.1:${port}/hook/stop`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    assert.equal(res.status, 200);

    const event = await received;
    assert.equal(event.sessionId, "abc-123");
    assert.equal(event.lastMessage, "I'm done, what's next?");
  });

  it("ignores payloads with stop_hook_active=true", async () => {
    server = new HookServer();
    const port = await server.start();

    let emitted = false;
    server.on("stop", () => {
      emitted = true;
    });

    const payload = {
      session_id: "abc-123",
      hook_event_name: "Stop",
      stop_hook_active: true,
      last_assistant_message: "test",
    };

    await fetch(`http://127.0.0.1:${port}/hook/stop`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    // Give it a moment to process
    await new Promise((r) => setTimeout(r, 50));
    assert.equal(emitted, false);
  });

  it("returns 404 for unknown routes", async () => {
    server = new HookServer();
    const port = await server.start();

    const res = await fetch(`http://127.0.0.1:${port}/unknown`);
    assert.equal(res.status, 404);
  });

  it("handles malformed JSON gracefully", async () => {
    server = new HookServer();
    const port = await server.start();

    const res = await fetch(`http://127.0.0.1:${port}/hook/stop`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "not json{{{",
    });
    assert.equal(res.status, 200); // Still returns 200, just ignores
  });
});
