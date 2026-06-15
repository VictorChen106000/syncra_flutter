const functions = require("firebase-functions");
const admin = require("firebase-admin");

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const MAX_PAGES = 8;
const MAX_BODY_CHARS = 500000;
const FETCH_TIMEOUT_MS = 8000;

const BLOCKED_HOST_PARTS = [
  "linkedin.com",
  "facebook.com",
  "instagram.com",
  "twitter.com",
  "x.com",
  "indeed.com",
  "glassdoor.com",
  "monster.com",
  "ziprecruiter.com",
  "reddit.com",
  "medium.com",
];

const HIGH_LOCAL_PARTS = [
  "careers",
  "jobs",
  "recruiting",
  "recruitment",
  "talent",
  "join",
];

const MEDIUM_LOCAL_PARTS = [
  "hr",
  "people",
  "work",
  "contact",
  "hiring",
];

const LOW_LOCAL_PARTS = [
  "info",
  "hello",
  "support",
];

const BAD_LOCAL_PARTS = [
  "noreply",
  "no-reply",
  "privacy",
  "abuse",
  "security",
  "admin",
  "webmaster",
  "postmaster",
];

function setCors(res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
}

function sendJson(res, status, body) {
  res.status(status).set("Content-Type", "application/json").send(body);
}

async function verifyAuth(req) {
  const header = String(req.headers.authorization || "");
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    throw new Error("Missing bearer token.");
  }
  await admin.auth().verifyIdToken(match[1]);
}

function cleanString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function isBlockedHost(hostname) {
  const host = hostname.toLowerCase();
  return BLOCKED_HOST_PARTS.some(
    (blocked) => host === blocked || host.endsWith(`.${blocked}`)
  );
}

function safeUrl(raw) {
  try {
    const url = new URL(raw);
    if (url.protocol !== "https:" && url.protocol !== "http:") {
      return null;
    }
    if (isBlockedHost(url.hostname)) {
      return null;
    }
    return url;
  } catch (_) {
    return null;
  }
}

function normalizeHost(hostname) {
  return hostname.toLowerCase().replace(/^www\./, "");
}

function registeredDomain(hostname) {
  const host = normalizeHost(hostname);
  const parts = host.split(".").filter(Boolean);

  if (parts.length <= 2) {
    return host;
  }

  const lastTwo = parts.slice(-2).join(".");
  const lastThree = parts.slice(-3).join(".");

  const secondLevelSuffixes = [
    "co.uk",
    "com.au",
    "com.tw",
    "com.sg",
    "co.jp",
    "com.hk",
    "com.mm",
  ];

  if (secondLevelSuffixes.includes(lastTwo) && parts.length >= 3) {
    return lastThree;
  }

  return lastTwo;
}

function sameRegisteredDomain(a, b) {
  return registeredDomain(a.hostname) === registeredDomain(b.hostname);
}

function candidateUrls(website, applyLink) {
  const seeds = [];

  const websiteUrl = safeUrl(website);
  const applyUrl = safeUrl(applyLink);

  if (websiteUrl) {
    seeds.push(websiteUrl);
  }

  if (applyUrl && (!websiteUrl || sameRegisteredDomain(applyUrl, websiteUrl))) {
    seeds.push(applyUrl);
  }

  const base = websiteUrl || applyUrl;
  if (!base) {
    return [];
  }

  const paths = [
    "/",
    "/careers",
    "/jobs",
    "/contact",
    "/about",
    "/company",
    "/team",
    "/people",
    "/press",
  ];

  for (const path of paths) {
    seeds.push(new URL(path, `${base.protocol}//${base.hostname}`));
  }

  const seen = new Set();

  return seeds
    .filter((url) => sameRegisteredDomain(url, base))
    .filter((url) => {
      const key = url.toString().replace(/\/$/, "");
      if (seen.has(key)) {
        return false;
      }
      seen.add(key);
      return true;
    })
    .slice(0, MAX_PAGES);
}

async function fetchText(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

  try {
    const response = await fetch(url, {
      method: "GET",
      redirect: "follow",
      signal: controller.signal,
      headers: {
        "User-Agent": "SyncraRecipientDiscovery/1.0",
        Accept: "text/html,text/plain;q=0.8,*/*;q=0.2",
      },
    });

    if (!response.ok) {
      return "";
    }

    const contentType = response.headers.get("content-type") || "";
    if (
      !contentType.includes("text/html") &&
      !contentType.includes("text/plain")
    ) {
      return "";
    }

    const text = await response.text();
    return text.slice(0, MAX_BODY_CHARS);
  } catch (_) {
    return "";
  } finally {
    clearTimeout(timer);
  }
}

function decodeHtmlLite(value) {
  return value
    .replace(/&commat;/gi, "@")
    .replace(/&#64;/g, "@")
    .replace(/&period;/gi, ".")
    .replace(/&#46;/g, ".")
    .replace(/&nbsp;/gi, " ");
}

function normalizeObfuscatedEmails(text) {
  return text
    .replace(/\s*\[\s*at\s*\]\s*/gi, "@")
    .replace(/\s*\(\s*at\s*\)\s*/gi, "@")
    .replace(/\s+at\s+/gi, "@")
    .replace(/\s*\[\s*dot\s*\]\s*/gi, ".")
    .replace(/\s*\(\s*dot\s*\)\s*/gi, ".")
    .replace(/\s+dot\s+/gi, ".");
}

function extractEmails(text) {
  const clean = normalizeObfuscatedEmails(decodeHtmlLite(text));
  const matches =
    clean.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi) || [];

  return [...new Set(matches.map((email) => email.toLowerCase()))];
}

function classifyEmail(email, sourceUrl, baseDomain) {
  const parts = email.split("@");
  const local = String(parts[0] || "").toLowerCase();
  const domain = String(parts[1] || "").toLowerCase().replace(/^www\./, "");

  if (!local || !domain) {
    return null;
  }

  if (registeredDomain(domain) !== baseDomain) {
    return null;
  }

  if (BAD_LOCAL_PARTS.some((bad) => local === bad || local.includes(bad))) {
    return null;
  }

  let confidence = "low";
  let score = 10;

  if (HIGH_LOCAL_PARTS.some((part) => local === part || local.includes(part))) {
    confidence = "high";
    score = 100;
  } else if (
    MEDIUM_LOCAL_PARTS.some((part) => local === part || local.includes(part))
  ) {
    confidence = "medium";
    score = 70;
  } else if (
    LOW_LOCAL_PARTS.some((part) => local === part || local.includes(part))
  ) {
    confidence = "low";
    score = 35;
  } else {
    return null;
  }

  const path = sourceUrl.pathname.toLowerCase();

  if (
    path.includes("career") ||
    path.includes("job") ||
    path.includes("join")
  ) {
    score += 15;
  }

  if (path.includes("contact")) {
    score += 5;
  }

  return {
    email,
    domain,
    local,
    confidence,
    sourceUrl: sourceUrl.toString(),
    score,
  };
}

function responseFor(candidate, fallbackDomain) {
  if (!candidate) {
    return {
      email: "",
      domain: fallbackDomain || "",
      confidence: "none",
      source: "none",
      label: "No public email found",
      reason: "No official company recipient email was found.",
      canAutoSend: false,
      requiresUserConfirmation: true,
    };
  }

  const high = candidate.confidence === "high";

  return {
    email: candidate.email,
    domain: candidate.domain,
    confidence: candidate.confidence,
    source: "officialCompanyWebsite",
    label: high ? "Found on official site" : "Needs confirmation",
    sourceUrl: candidate.sourceUrl,
    reason: `Found ${candidate.email} on an official company page.`,
    canAutoSend: high,
    requiresUserConfirmation: !high,
  };
}

exports.companyContactDiscovery = functions
  .region("us-central1")
  .runWith({
    timeoutSeconds: 30,
    memory: "256MB",
  })
  .https.onRequest(async (req, res) => {
    setCors(res);

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    if (req.method !== "POST") {
      sendJson(res, 405, { error: "Method not allowed." });
      return;
    }

    try {
      await verifyAuth(req);
    } catch (_) {
      sendJson(res, 401, { error: "Unauthorized." });
      return;
    }

    const company = cleanString(req.body && req.body.company);
    const website = cleanString(req.body && req.body.website);
    const applyLink = cleanString(req.body && req.body.applyLink);

    if (!company && !website && !applyLink) {
      sendJson(res, 200, responseFor(null));
      return;
    }

    const urls = candidateUrls(website, applyLink);
    const base = urls[0];

    if (!base) {
      sendJson(res, 200, responseFor(null));
      return;
    }

    const baseDomain = registeredDomain(base.hostname);
    const candidates = [];

    for (const url of urls) {
      const text = await fetchText(url);
      if (!text) {
        continue;
      }

      for (const email of extractEmails(text)) {
        const candidate = classifyEmail(email, url, baseDomain);
        if (candidate) {
          candidates.push(candidate);
        }
      }
    }

    candidates.sort((a, b) => b.score - a.score);

    sendJson(res, 200, responseFor(candidates[0] || null, baseDomain));
  });