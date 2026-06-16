const assert = require("node:assert/strict");
const test = require("node:test");

const { __testables } = require("./companyContactDiscovery");

test("discoveryPlan uses the official website before an apply link", () => {
  const plan = __testables.discoveryPlan(
    "https://www.acme.io/openings",
    "https://greenhouse.io/acme/jobs/123"
  );

  assert.equal(plan.officialDomain, "acme.io");
  assert.equal(plan.urls.length, __testables.DISCOVERY_PATHS.length);
  assert.ok(plan.urls.every((url) => url.hostname === "www.acme.io"));
  assert.ok(plan.urls.some((url) => url.pathname === "/contact-us"));
  assert.ok(plan.urls.some((url) => url.pathname === "/join-us"));
});

test("extractEmails decodes simple obfuscation", () => {
  const emails = __testables.extractEmails(
    "Reach jobs [at] acme [dot] io or talent(at)acme(dot)io."
  );

  assert.deepEqual(emails, ["jobs@acme.io", "talent@acme.io"]);
});

test("ranking prefers official role inboxes and keeps generic inboxes medium", () => {
  const officialDomain = "acme.io";
  const role = __testables.classifyEmail(
    "jobs@acme.io",
    new URL("https://acme.io/jobs"),
    officialDomain
  );
  const generic = __testables.classifyEmail(
    "hello@acme.io",
    new URL("https://acme.io/contact"),
    officialDomain
  );
  const bad = __testables.classifyEmail(
    "legal@acme.io",
    new URL("https://acme.io/contact"),
    officialDomain
  );
  const external = __testables.classifyEmail(
    "jobs@example.com",
    new URL("https://acme.io/jobs"),
    officialDomain
  );

  assert.equal(bad, null);
  assert.equal(external, null);
  assert.equal(role.confidence, "high");
  assert.equal(generic.confidence, "medium");

  const ranked = __testables.rankCandidates([generic, role]);
  assert.equal(ranked[0].email, "jobs@acme.io");

  const roleResponse = __testables.responseFor(role, officialDomain);
  assert.equal(roleResponse.canAutoSend, true);
  assert.equal(roleResponse.requiresUserConfirmation, false);

  const genericResponse = __testables.responseFor(generic, officialDomain);
  assert.equal(genericResponse.canAutoSend, false);
  assert.equal(genericResponse.requiresUserConfirmation, true);
});
