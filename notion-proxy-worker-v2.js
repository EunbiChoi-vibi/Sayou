// notion-proxy-worker.js
//
// Deploy this on Cloudflare Workers (free plan is enough).
// Notion's API blocks direct calls from a browser (CORS), so this worker
// calls Notion on the server side instead, and adds CORS headers on the way back.
//
// Setup:
// 1. In this worker: Settings -> Variables and Secrets -> Add variable
//      Name:  NOTION_SECRET
//      Value: your Notion integration secret (starts with secret_ or ntn_)
//      Type:  Secret
// 2. Copy this worker's URL (shown at the top, like https://xxx.workers.dev)
// 3. Paste that URL into the dashboard's "프록시 서버(Worker) 주소" field
//
// Notion-side setup:
// 1. https://www.notion.so/my-integrations -> New integration -> copy the secret
// 2. Open each Notion database to sync -> "..." menu -> Connections -> add your integration
// 3. Copy the database ID from its URL (the 32-character id before ?v=...)

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET,POST,PATCH,DELETE,OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Notion-Version",
          "Access-Control-Max-Age": "86400",
        },
      });
    }

    if (!env.NOTION_SECRET) {
      return new Response(
        JSON.stringify({ error: "NOTION_SECRET is not configured on this worker." }),
        { status: 500, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    const url = new URL(request.url);
    const notionUrl = "https://api.notion.com" + url.pathname + url.search;

    const forwardedHeaders = new Headers();
    forwardedHeaders.set("Authorization", "Bearer " + env.NOTION_SECRET);
    forwardedHeaders.set("Notion-Version", "2022-06-28");
    const incomingContentType = request.headers.get("Content-Type");
    if (incomingContentType) forwardedHeaders.set("Content-Type", incomingContentType);

    const init = {
      method: request.method,
      headers: forwardedHeaders,
    };
    if (request.method !== "GET" && request.method !== "HEAD") {
      init.body = await request.text();
    }

    const notionResponse = await fetch(notionUrl, init);

    const responseHeaders = new Headers(notionResponse.headers);
    responseHeaders.set("Access-Control-Allow-Origin", "*");
    responseHeaders.delete("content-encoding");
    responseHeaders.delete("content-length");

    return new Response(notionResponse.body, {
      status: notionResponse.status,
      headers: responseHeaders,
    });
  },
};
