"use strict";

/**
 * Syncra API-key proxy.
 *
 * Two HTTPS functions stand in front of the third-party APIs so the client
 * never ships the keys. Each verifies the caller's Firebase ID token, then
 * injects the real key (from Cloud Secret Manager) and forwards the request.
 * Responses are passed back verbatim — same status code and `retry-after`
 * header — so the Flutter client's existing retry/backoff logic still works.
 *
 * Secrets (set once via the CLI, never committed):
 *   firebase functions:secrets:set ANTHROPIC_API_KEY
 *   firebase functions:secrets:set RAPIDAPI_KEY
 */

const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");

admin.initializeApp();

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const RAPIDAPI_KEY = defineSecret("RAPIDAPI_KEY");

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const JSEARCH_HOST = "jsearch.p.rapidapi.com";

/**
 * Verifies the `Authorization: Bearer <firebase-id-token>` header. On success
 * returns the decoded token; on failure writes a 401 and returns null so the
 * caller can simply `return`.
 */
async function requireUser(req, res) {
  const header = req.get("authorization") || "";
  const match = header.match(/^Bearer (.+)$/i);
  if (!match) {
    res.status(401).json({ error: { message: "Missing bearer token." } });
    return null;
  }
  try {
    return await admin.auth().verifyIdToken(match[1]);
  } catch (e) {
    res.status(401).json({ error: { message: "Invalid or expired token." } });
    return null;
  }
}

exports.anthropicProxy = onRequest(
  { secrets: [ANTHROPIC_API_KEY], cors: true, timeoutSeconds: 120 },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: { message: "Use POST." } });
      return;
    }
    if (!(await requireUser(req, res))) return;

    try {
      const upstream = await fetch(ANTHROPIC_URL, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-api-key": ANTHROPIC_API_KEY.value(),
          "anthropic-version": ANTHROPIC_VERSION,
        },
        body: JSON.stringify(req.body),
      });

      const text = await upstream.text();
      const retryAfter = upstream.headers.get("retry-after");
      if (retryAfter) res.set("retry-after", retryAfter);
      res.status(upstream.status).type("application/json").send(text);
    } catch (e) {
      res.status(502).json({ error: { message: `Upstream error: ${e}` } });
    }
  }
);

exports.jsearchProxy = onRequest(
  { secrets: [RAPIDAPI_KEY], cors: true, timeoutSeconds: 30 },
  async (req, res) => {
    if (!(await requireUser(req, res))) return;

    const params = new URLSearchParams(req.query).toString();
    try {
      const upstream = await fetch(`https://${JSEARCH_HOST}/search?${params}`, {
        method: "GET",
        headers: {
          "X-RapidAPI-Key": RAPIDAPI_KEY.value(),
          "X-RapidAPI-Host": JSEARCH_HOST,
        },
      });

      const text = await upstream.text();
      res.status(upstream.status).type("application/json").send(text);
    } catch (e) {
      res.status(502).json({ error: { message: `Upstream error: ${e}` } });
    }
  }
);

exports.companyContactDiscovery =
  require("./companyContactDiscovery").companyContactDiscovery;