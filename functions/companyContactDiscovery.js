const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const MAX_BODY_CHARS = 120000;
const FETCH_TIMEOUT_MS = 2500;
const MAX_REDIRECTS = 2;

const DISCOVERY_PATHS = [
  "/",
  "/careers",
  "/jobs",
  "/contact",
  "/contact-us",
  "/about",
  "/team",
  "/recruiting",
  "/join-us",
];

const BLOCKED_HOST_PARTS = [
  "linkedin.com",
  "facebook.com",
  "instagram.com",
  "twitter.com",
  "x.com",
  "tiktok.com",
  "youtube.com",
  "indeed.com",
  "glassdoor.com",
  "monster.com",
  "ziprecruiter.com",
  "greenhouse.io",
  "lever.co",
  "ashbyhq.com",
  "workable.com",
  "smartrecruiters.com",
  "myworkdayjobs.com",
  "workdayjobs.com",
  "jobvite.com",
  "icims.com",
  "bamboohr.com",
  "breezy.hr",
  "comeet.co",
  "recruitee.com",
  "wellfound.com",
  "angel.co",
  "reddit.com",
  "medium.com",
];

const ROLE_INBOX_PARTS = [
  "careers",
  "jobs",
  "talent",
  "recruiting",
  "recruitment",
  "hr",
  "people",
];

const GENERIC_INBOX_PARTS = [
  "contact",
  "info",
  "hello",
];

const BAD_LOCAL_PARTS = [
  "noreply",
  "no-reply",
  "privacy",
  "legal",
  "press",
  "media",
  "sales",
  "billing",
  "security",
  "abuse",
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
  const clean = cleanString(raw);
  if (!clean) {
    return null;
  }

  try {
    const withScheme = /^[a-z][a-z0-9+.-]*:\/\//i.test(clean)
      ? clean
      : `https://${clean}`;
    const url = new URL(withScheme);
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

function officialBaseUrl(website, applyLink) {
  const websiteUrl = safeUrl(website);
  if (websiteUrl) {
    return websiteUrl;
  }

  return safeUrl(applyLink);
}

function isOfficialUrl(url, officialDomain) {
  return (
    url &&
    !isBlockedHost(url.hostname) &&
    registeredDomain(url.hostname) === officialDomain
  );
}

function discoveryPlan(website, applyLink) {
  const base = officialBaseUrl(website, applyLink);
  if (!base) {
    return { urls: [], officialDomain: "" };
  }

  const officialDomain = registeredDomain(base.hostname);
  const origin = `${base.protocol}//${base.hostname}`;
  const seen = new Set();

  const urls = DISCOVERY_PATHS.map((path) => new URL(path, origin))
    .filter((url) => isOfficialUrl(url, officialDomain))
    .filter((url) => {
      const key = url.toString().replace(/\/$/, "");
      if (seen.has(key)) {
        return false;
      }
      seen.add(key);
      return true;
    });

  return { urls, officialDomain };
}

async function readLimitedText(response) {
  if (!response.body || typeof response.body.getReader !== "function") {
    const text = await response.text();
    return text.slice(0, MAX_BODY_CHARS);
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let text = "";

  try {
    while (text.length < MAX_BODY_CHARS) {
      const { value, done } = await reader.read();
      if (done) {
        break;
      }
      text += decoder.decode(value, { stream: true });
      if (text.length >= MAX_BODY_CHARS) {
        await reader.cancel();
        break;
      }
    }

    text += decoder.decode();
    return text.slice(0, MAX_BODY_CHARS);
  } catch (_) {
    return text.slice(0, MAX_BODY_CHARS);
  }
}

async function fetchOfficialPage(url, officialDomain) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  let current = url;

  try {
    for (let redirectCount = 0; redirectCount <= MAX_REDIRECTS; redirectCount++) {
      if (!isOfficialUrl(current, officialDomain)) {
        return null;
      }

      const response = await fetch(current, {
        method: "GET",
        redirect: "manual",
        signal: controller.signal,
        headers: {
          "User-Agent": "SyncraRecipientDiscovery/1.0",
          Accept: "text/html,text/plain;q=0.8,*/*;q=0.2",
        },
      });

      if (response.status >= 300 && response.status < 400) {
        const location = response.headers.get("location");
        if (!location) {
          return null;
        }
        const next = safeUrl(new URL(location, current).toString());
        if (!isOfficialUrl(next, officialDomain)) {
          return null;
        }
        current = next;
        continue;
      }

      if (!response.ok) {
        return null;
      }

      const contentType = response.headers.get("content-type") || "";
      if (
        contentType &&
        !contentType.includes("text/html") &&
        !contentType.includes("text/plain")
      ) {
        return null;
      }

      return {
        text: await readLimitedText(response),
        sourceUrl: current,
      };
    }

    return null;
  } catch (_) {
    return null;
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

function localHasPart(local, part) {
  return local === part || local.includes(part);
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

  let confidence = "medium";
  let score = 10;

  if (ROLE_INBOX_PARTS.some((part) => localHasPart(local, part))) {
    confidence = "high";
    score = 100;
  } else if (GENERIC_INBOX_PARTS.some((part) => localHasPart(local, part))) {
    confidence = "medium";
    score = 60;
  } else {
    return null;
  }

  const path = sourceUrl.pathname.toLowerCase();

  if (
    path.includes("career") ||
    path.includes("job") ||
    path.includes("recruit") ||
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

function rankCandidates(candidates) {
  return [...candidates].sort((a, b) => b.score - a.score);
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

    const { urls, officialDomain } = discoveryPlan(website, applyLink);

    if (urls.length === 0 || !officialDomain) {
      sendJson(res, 200, responseFor(null));
      return;
    }

    const candidates = [];

    for (const url of urls) {
      const page = await fetchOfficialPage(url, officialDomain);
      if (!page || !page.text) {
        continue;
      }

      for (const email of extractEmails(page.text)) {
        const candidate = classifyEmail(email, page.sourceUrl, officialDomain);
        if (candidate) {
          candidates.push(candidate);
        }
      }
    }

    const ranked = rankCandidates(candidates);

    sendJson(res, 200, responseFor(ranked[0] || null, officialDomain));
  });

exports.__testables = {
  DISCOVERY_PATHS,
  BLOCKED_HOST_PARTS,
  safeUrl,
  registeredDomain,
  sameRegisteredDomain,
  officialBaseUrl,
  isOfficialUrl,
  discoveryPlan,
  decodeHtmlLite,
  normalizeObfuscatedEmails,
  extractEmails,
  classifyEmail,
  rankCandidates,
  responseFor,
};
