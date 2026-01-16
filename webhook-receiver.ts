#!/usr/bin/env -S deno run --allow-net --allow-run

const PORT = 23614;
const TRIGGER_SCRIPT = "/opt/declare-sh/trigger-restore.sh";
const RATE_LIMIT_WINDOW = 60000; // 1 minute
const MAX_TRIGGERS_PER_WINDOW = 3;

// Simple global rate limiting for valid push events
let triggerCount = 0;
let windowStart = Date.now();

async function handleWebhook(req: Request): Promise<Response> {
  const url = new URL(req.url);

  if (url.pathname === "/webhook" && req.method === "POST") {
    console.log(`[${new Date().toISOString()}] Webhook received`);

    try {
      // Validate GitHub webhook structure
      const event = req.headers.get("X-GitHub-Event");
      const delivery = req.headers.get("X-GitHub-Delivery");

      if (!event || !delivery) {
        console.log(`[${new Date().toISOString()}] Rejected: Missing GitHub headers`);
        return new Response("Invalid request", { status: 400 });
      }

      // Only process push events
      if (event !== "push") {
        console.log(`[${new Date().toISOString()}] Ignored: ${event} event`);
        return new Response(
          JSON.stringify({ status: "ignored", reason: `Not a push event: ${event}` }),
          { status: 200, headers: { "Content-Type": "application/json" } }
        );
      }

      // Parse payload to check branch
      const payload = await req.json();
      const ref = payload.ref;

      // Only trigger on main branch pushes
      if (ref !== "refs/heads/main") {
        console.log(`[${new Date().toISOString()}] Ignored: push to ${ref}`);
        return new Response(
          JSON.stringify({ status: "ignored", reason: `Not main branch: ${ref}` }),
          { status: 200, headers: { "Content-Type": "application/json" } }
        );
      }

      // Apply rate limiting for valid push events
      const now = Date.now();
      if (now - windowStart > RATE_LIMIT_WINDOW) {
        // Reset window
        windowStart = now;
        triggerCount = 0;
      }

      if (triggerCount >= MAX_TRIGGERS_PER_WINDOW) {
        console.log(`[${new Date().toISOString()}] Rate limited`);
        return new Response(
          JSON.stringify({ status: "rate_limited", message: "Too many triggers" }),
          { status: 429, headers: { "Content-Type": "application/json" } }
        );
      }

      triggerCount++;

      console.log(`[${new Date().toISOString()}] Valid push to main - triggering restore`);

      // Trigger the restore script
      const command = new Deno.Command("bash", {
        args: [TRIGGER_SCRIPT],
        stdout: "piped",
        stderr: "piped",
      });

      const process = command.spawn();
      const { code, stdout, stderr } = await process.output();

      const stdoutText = new TextDecoder().decode(stdout);
      const stderrText = new TextDecoder().decode(stderr);

      console.log(`[${new Date().toISOString()}] Trigger script exit code: ${code}`);
      if (stdoutText) console.log("STDOUT:", stdoutText);
      if (stderrText) console.error("STDERR:", stderrText);

      return new Response(
        JSON.stringify({
          status: "triggered",
          exitCode: code,
          message: "Configuration update process initiated"
        }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }
      );
    } catch (error) {
      console.error(`[${new Date().toISOString()}] Error executing trigger script:`, error);
      return new Response(
        JSON.stringify({
          status: "error",
          message: String(error)
        }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        }
      );
    }
  }

  if (url.pathname === "/health" && req.method === "GET") {
    return new Response(
      JSON.stringify({ status: "healthy", timestamp: new Date().toISOString() }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }
    );
  }

  return new Response("Not Found", { status: 404 });
}

console.log(`Webhook receiver listening on port ${PORT}`);
console.log(`Endpoints:`);
console.log(`  POST /webhook - Trigger configuration restore`);
console.log(`  GET  /health  - Health check`);

Deno.serve({ hostname: "::", port: PORT }, handleWebhook);
