import { describe, test, expect } from "bun:test";

const BASE = "http://localhost:24100";

describe("GET /commands", () => {
  test("returns array of command names", async () => {
    const res = await fetch(`${BASE}/commands`);
    expect(res.status).toBe(200);
    const names = await res.json();
    expect(Array.isArray(names)).toBe(true);
    expect(names).toContain("Uppercase");
  });
});

describe("POST /transform", () => {
  test("uppercase transforms text", async () => {
    const res = await fetch(`${BASE}/transform`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ command: "Uppercase", text: "hello" }),
    });
    expect(res.status).toBe(200);
    const { result } = await res.json();
    expect(result).toBe("HELLO");
  });

  test("missing fields returns 400", async () => {
    const res = await fetch(`${BASE}/transform`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ command: "uppercase" }),
    });
    expect(res.status).toBe(400);
  });

  test("accepts extra args", async () => {
    const res = await fetch(`${BASE}/transform`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        command: "Uppercase",
        text: "hello",
        args: { context: "test_value" },
      }),
    });
    expect(res.status).toBe(200);
    const { result } = await res.json();
    expect(result).toBe("HELLO");
  });

  test("unknown command returns 500", async () => {
    const res = await fetch(`${BASE}/transform`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ command: "nonexistent", text: "hi" }),
    });
    expect(res.status).toBe(500);
  });
});

describe("routing", () => {
  test("unknown path returns 404", async () => {
    const res = await fetch(`${BASE}/bogus`);
    expect(res.status).toBe(404);
  });

  test("CORS preflight returns 204", async () => {
    const res = await fetch(`${BASE}/transform`, { method: "OPTIONS" });
    expect(res.status).toBe(204);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe("*");
  });
});
