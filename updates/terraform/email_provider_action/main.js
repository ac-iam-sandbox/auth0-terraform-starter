const { SESv2Client, SendEmailCommand } = require("@aws-sdk/client-sesv2");

// Cache the Management API token across warm invocations
let cachedToken = null;
let tokenExpiresAt = 0;

async function getManagementToken(domain, clientId, clientSecret) {
  if (cachedToken && Date.now() < tokenExpiresAt) return cachedToken;

  const res = await fetch(`https://${domain}/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      grant_type: "client_credentials",
      client_id: clientId,
      client_secret: clientSecret,
      audience: `https://${domain}/api/v2/`,
    }),
  });

  if (!res.ok) throw new Error(`Token request failed: ${res.status}`);

  const data = await res.json();
  cachedToken = data.access_token;
  // Expire 5 min early to be safe
  tokenExpiresAt = Date.now() + (data.expires_in - 300) * 1000;
  return cachedToken;
}

async function createPasswordChangeTicket(domain, token, userId) {
  const res = await fetch(`https://${domain}/api/v2/tickets/password-change`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      user_id: `auth0|${userId}`,
      ttl_sec: 432000,
      mark_email_as_verified: false,
    }),
  });

  if (!res.ok) throw new Error(`Ticket creation failed: ${res.status}`);

  const data = await res.json();
  return data.ticket;
}

exports.onExecuteCustomEmailProvider = async (event, api) => {
  let html = event.notification.html;
  let text = event.notification.text;

  if (event.notification.message_type === "blocked_account") {
    try {
      const token = await getManagementToken(
        event.secrets.AUTH0_DOMAIN,
        event.secrets.AUTH0_CLIENT_ID,
        event.secrets.AUTH0_CLIENT_SECRET
      );

      const ticketUrl = await createPasswordChangeTicket(
        event.secrets.AUTH0_DOMAIN,
        token,
        event.user.user_id
      );

      html = html.replace("%%CHANGE_PASSWORD_URL%%", ticketUrl);
      text = text.replace("%%CHANGE_PASSWORD_URL%%", ticketUrl);
    } catch (err) {
      api.notification.retry(
        `Failed to create password change ticket: ${err.message}`.slice(0, 1024)
      );
      return;
    }
  }

  const ses = new SESv2Client({
    region: event.secrets.AWS_REGION,
    credentials: {
      accessKeyId: event.secrets.AWS_ACCESS_KEY_ID,
      secretAccessKey: event.secrets.AWS_SECRET_ACCESS_KEY,
    },
  });

  const command = new SendEmailCommand({
    FromEmailAddress: event.notification.from,
    Destination: { ToAddresses: [event.notification.to] },
    Content: {
      Simple: {
        Subject: { Data: event.notification.subject, Charset: "UTF-8" },
        Body: {
          Html: { Data: html, Charset: "UTF-8" },
          Text: { Data: text, Charset: "UTF-8" },
        },
      },
    },
  });

  try {
    await ses.send(command);
  } catch (error) {
    if (error.$retryable || error.name === "TooManyRequestsException" || (error.$metadata?.httpStatusCode >= 500)) {
      api.notification.retry(`SES transient error: ${error.name} — ${error.message}`.slice(0, 1024));
      return;
    }
    api.notification.drop(`SES permanent error: ${error.name} — ${error.message}`.slice(0, 1024));
  }
};
