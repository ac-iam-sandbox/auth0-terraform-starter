/**
 * Action:  Link Accounts
 * Trigger: Post Login
 *
 * Handles:
 *   - LINE users whose email was just captured by profiling in Action 1
 *   - DB users with verified email checking for social matches
 *
 * Module dependencies:
 *   - account-linking
 *
 * Secrets:
 *   - LINKING_FORM_ID
 */

const {
  LINKING_DONE_KEY,
  LINKING_PERFORMED,
  connectionLabel,
  resolveEmail,
  isDatabaseStrategy,
  findAllLinkCandidates,
  buildLinkPlan,
  searchUsersByEmail,
  executeLinkPlan,
} = require("actions:account-linking");

const TX_ENTRY_PATH_VALID = "entry_path_valid";
const TX_LINKING_CHECKED = "linking_checked";

function denyWithLogout(event, api, errorCode, errorMessage) {
  const appUrl = new URL(event.transaction.redirect_uri);
  appUrl.searchParams.set("error", errorCode);
  appUrl.searchParams.set("error_description", errorMessage);

  const logoutUrl =
    `https://${event.request.hostname}/v2/logout` +
    `?client_id=${event.client.client_id}` +
    `&returnTo=${encodeURIComponent(appUrl.toString())}`;

  api.redirect.sendUserTo(logoutUrl);
}

function hasValidEntryPath(event) {
  const txResult = event.transaction?.metadata?.[TX_ENTRY_PATH_VALID];
  if (txResult === "true") return true;

  const appMeta = event.user.app_metadata || {};
  if (appMeta.entry_path) return true;

  return false;
}

exports.onExecutePostLogin = async (event, api) => {
  if (!event.client?.metadata?.signup_profile) return;
  if (!event.secrets.LINKING_FORM_ID) return;

  const appMeta = event.user.app_metadata || {};

  if (appMeta[LINKING_DONE_KEY]) return;

  if (appMeta.registration_completed === true && appMeta.entry_path) return;

  if (event.transaction?.metadata?.[TX_LINKING_CHECKED] === "true") return;

  if (event.transaction?.protocol === "oauth2-refresh-token") return;

  if (
    isDatabaseStrategy(event.connection.strategy) &&
    !event.user.email_verified
  )
    return;

  const email = resolveEmail(event);

  if (!email) {
    if (!hasValidEntryPath(event)) {
      console.log("No email and no valid entry path — denying");
      denyWithLogout(
        event,
        api,
        "entry_path_missing",
        "A registration path is required. Please use a valid registration link."
      );
    }
    return;
  }

  try {
    const allUsers = await searchUsersByEmail(api, email);
    const candidates = findAllLinkCandidates(
      allUsers,
      event.user.user_id,
      email
    );

    if (candidates.length === 0) {
      api.transaction.setMetadata(TX_LINKING_CHECKED, "true");

      if (!hasValidEntryPath(event)) {
        console.log("No link candidates and no valid entry path — denying");
        denyWithLogout(
          event,
          api,
          "entry_path_missing",
          "A registration path is required. Please use a valid registration link."
        );
      } else {
        api.user.setAppMetadata("registration_completed", true);
        api.user.setAppMetadata("registered_at", new Date().toISOString());
      }
      return;
    }

    const plan = buildLinkPlan(event, candidates);
    const labels = candidates.map((c) =>
      connectionLabel(c.identities[0].provider)
    );

    api.prompt.render(event.secrets.LINKING_FORM_ID, {
      fields: {
        email,
        connection_type: connectionLabel(event.connection.strategy),
        existing_accounts: labels.join(", "),
        account_count: String(candidates.length),
      },
      vars: {
        form_type: "linking",
        link_email_used: email,
        link_plan: JSON.stringify({
          primary_user_id: plan.primary.user_id,
          secondaries: plan.secondaries.map((s) => ({
            user_id: s.user_id,
            provider: s.provider,
          })),
        }),
      },
    });
  } catch (err) {
    console.log("Linking error:", err?.message || "unknown");
  }
};

exports.onContinuePostLogin = async (event, api) => {
  const linkEmail = event.prompt?.fields?.link_email;

  // ── User cancelled linking ──
  if (linkEmail === "false" || linkEmail === false) {
    api.user.setAppMetadata("linking_cancelled_at", new Date().toISOString());

    api.transaction.setMetadata(TX_LINKING_CHECKED, "true");

    if (!hasValidEntryPath(event)) {
      denyWithLogout(
        event,
        api,
        "linking_cancelled",
        "Account linking was cancelled and no valid registration path was found."
      );
    } else {
      denyWithLogout(
        event,
        api,
        "linking_cancelled",
        "Account linking was cancelled. Please try again."
      );
    }
    return;
  }

  if (linkEmail !== "true" && linkEmail !== true) {
    denyWithLogout(
      event,
      api,
      "linking_failed",
      "We were unable to complete account linking. Please try again."
    );
    return;
  }

  let plan;
  try {
    plan = JSON.parse(event.prompt?.vars?.link_plan || "{}");
  } catch {
    denyWithLogout(
      event,
      api,
      "linking_failed",
      "We were unable to complete account linking. Please try again."
    );
    return;
  }

  if (!plan.primary_user_id || !plan.secondaries?.length) {
    denyWithLogout(
      event,
      api,
      "linking_failed",
      "We were unable to complete account linking. Please try again."
    );
    return;
  }

  let allUsers = [];
  const linkEmailUsed = event.prompt?.vars?.link_email_used;
  if (linkEmailUsed) {
    try {
      allUsers = await searchUsersByEmail(api, linkEmailUsed);
      const currentInResults = allUsers.some(
        (u) => u.user_id === event.user.user_id
      );
      if (!currentInResults) {
        allUsers.push({
          user_id: event.user.user_id,
          app_metadata: event.user.app_metadata || {},
          user_metadata: event.user.user_metadata || {},
        });
      }
    } catch (err) {
      console.log("Re-fetch for merge failed:", err.message);
    }
  }

  const result = await executeLinkPlan(
    api,
    {
      primary: { user_id: plan.primary_user_id },
      secondaries: plan.secondaries,
    },
    { allUsers }
  );

  if (result.linked === 0) {
    console.log("Linking failed:", result.errors.join("; "));
    denyWithLogout(
      event,
      api,
      "linking_failed",
      "We were unable to complete account linking. Please try again."
    );
    return;
  }

  if (result.errors.length > 0) {
    console.log(
      "Partial link:",
      result.linked,
      "ok,",
      result.errors.length,
      "failed"
    );
  }

  if (event.user.user_id !== plan.primary_user_id) {
    api.authentication.setPrimaryUser(plan.primary_user_id);
  }

  api.transaction.setMetadata(LINKING_PERFORMED, true);
  api.user.setAppMetadata(LINKING_DONE_KEY, Date.now());
  api.user.setAppMetadata("linked_at", new Date().toISOString());
};
