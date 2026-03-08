# Okta Developer Account Setup for SPARC

This guide walks through creating a free Okta developer account and configuring it as an OIDC identity provider for SPARC.

## 1. Create an Okta Developer Account

1. Go to [https://developer.okta.com/signup/](https://developer.okta.com/signup/)
2. Fill out the registration form with your email and organization name
3. Check your email and verify your account
4. Log in to the Okta Admin Console

## 2. Create an OIDC Application

1. In the Admin Console, navigate to **Applications > Applications**
2. Click **Create App Integration**
3. Select:
   - **Sign-in method**: OIDC - OpenID Connect
   - **Application type**: Web Application
4. Click **Next**

## 3. Configure the Application

Fill in the following fields:

| Field | Value |
|-------|-------|
| App integration name | `SPARC (Development)` |
| Grant type | Authorization Code (default) |
| Sign-in redirect URIs | `http://localhost:3000/auth/oidc/callback` |
| Sign-out redirect URIs | `http://localhost:3000/login` |
| Initiate login URI | `http://localhost:3000/login` |
| Login initiated by | Either Okta or App |
| Controlled access | Skip group assignment for now |

Click **Save**.

## 4. Assign Users to the Application

**This step is required** — without it, Okta cannot evaluate token claims for your users.

1. On your new application page, go to the **Assignments** tab
2. Click **Assign → Assign to People**
3. Find your user and click **Assign** → **Save and Go Back** → **Done**

> **Important:** Even as an Okta admin, you must explicitly assign yourself to the application. Without this, the `sub` claim cannot be evaluated and login will fail with "Unknown error."

## 5. Configure the Authorization Server Access Policy

The default authorization server needs an access policy rule that allows your app to obtain tokens.

1. Go to **Security → API → Authorization Servers**
2. Click **default**
3. Go to the **Access Policies** tab
4. Click into the existing policy (or create one)
5. **Add a Rule** (or verify an existing one includes your app):

| Setting | Value |
|---------|-------|
| Rule Name | SPARC Access |
| Grant type | Authorization Code |
| User is | Any user assigned the app |
| Scopes requested | Any scopes |

> **Without this rule**, Okta will return "Policy evaluation failed for this request" when SPARC attempts to authenticate.

### Fix the `sub` Claim (if needed)

If you see "The 'sub' system claim could not be evaluated":

1. On the same **default** authorization server, go to the **Claims** tab
2. Find the `sub` claim and click the **pencil icon** to edit
3. Change the **Value** to: `user.email`
4. Save

The default expression `(appuser != null) ? appuser.userName : app.clientId` can fail if the app-to-user mapping isn't resolving correctly. Using `user.email` pulls directly from the authenticated user's profile and is more reliable for development.

---

## 6. Collect Credentials

After saving, you'll see the application details page. Note these values:

- **Client ID** — displayed on the General tab
- **Client secret** — displayed on the General tab (click the eye icon)
- **Issuer URL** — found under **Security > API > Authorization Servers**. It will look like: `https://dev-XXXXXXXX.okta.com/oauth2/default`

## 7. Configure SPARC

Add the following to your `.env` file:

```bash
SPARC_ENABLE_OIDC=true
SPARC_OIDC_ISSUER_URL=https://dev-XXXXXXXX.okta.com/oauth2/default
SPARC_OIDC_CLIENT_ID=0oaXXXXXXXXXXXXXXX
SPARC_OIDC_CLIENT_SECRET=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
SPARC_OIDC_PROVIDER_TITLE=Okta
```

**Important:** After updating `.env`, you must restart the Rails server. dotenv loads environment variables at boot time only.

## 8. Test the Integration

1. Start SPARC: `bin/rails server`
2. Navigate to `http://localhost:3000/login`
3. Click the **Okta** tab
4. Click **Sign in with Okta**
5. Authenticate with your Okta credentials
6. You should be redirected back to SPARC and signed in

## 9. Add Test Users

1. In the Okta Admin Console, go to **Directory > People**
2. Click **Add Person**
3. Fill in email, first name, last name
4. Set a password
5. Assign the person to your SPARC application under **Applications**

## 10. Enable MFA (Optional)

To test MFA enforcement:

1. Go to **Security > Authenticators**
2. Ensure at least one MFA factor is enrolled (e.g., Okta Verify, Google Authenticator)
3. Go to **Security > Authentication Policies**
4. Create or edit a policy for your SPARC application
5. Add a rule requiring MFA

## Troubleshooting

### "Authentication failed: csrf_detected"
OmniAuth requires POST requests for initiating OAuth. Ensure you're using `form_tag "/auth/oidc", method: :post` instead of a plain link.

### "No email returned from oidc"
Ensure the `email` scope is included in `SPARC_OIDC_SCOPES` (default: `openid profile email`) and that Okta is configured to share the user's email.

### "Invalid redirect URI"
The redirect URI in Okta must exactly match `http://localhost:3000/auth/oidc/callback` (including protocol and port).

### "Policy evaluation failed for this request"
The authorization server's access policy doesn't have a rule that allows your app. See [Step 5](#5-configure-the-authorization-server-access-policy) — add a rule with Authorization Code grant type for your app.

### "The 'sub' system claim could not be evaluated"
Two possible causes:
1. **User not assigned to the app** — Go to Applications → your app → Assignments and assign your user. See [Step 4](#4-assign-users-to-the-application).
2. **sub claim expression failing** — Edit the `sub` claim on the authorization server (Security → API → Authorization Servers → default → Claims) and change the value to `user.email`. See [Step 5](#5-configure-the-authorization-server-access-policy).

### "Authentication failed: Unknown error"
Check the Rails server logs for the specific OmniAuth error. Common causes are the `sub` claim or access policy issues above.

### Changes to `.env` not taking effect
dotenv-rails loads environment variables at boot time only. You must restart the Rails server after any `.env` change.

### Token errors
Ensure the **Issuer URL** points to the correct authorization server. The default is usually `https://dev-XXXXXXXX.okta.com/oauth2/default`.
