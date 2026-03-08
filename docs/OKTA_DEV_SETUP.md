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
| Sign-out redirect URIs | `http://localhost:3000` |
| Controlled access | Skip group assignment for now |

Click **Save**.

## 4. Collect Credentials

After saving, you'll see the application details page. Note these values:

- **Client ID** — displayed on the General tab
- **Client secret** — displayed on the General tab (click the eye icon)
- **Issuer URL** — found under **Security > API > Authorization Servers**. It will look like: `https://dev-XXXXXXXX.okta.com/oauth2/default`

## 5. Configure SPARC

Add the following to your `.env` file:

```bash
SPARC_ENABLE_OIDC=true
SPARC_OIDC_ISSUER_URL=https://dev-XXXXXXXX.okta.com/oauth2/default
SPARC_OIDC_CLIENT_ID=0oaXXXXXXXXXXXXXXX
SPARC_OIDC_CLIENT_SECRET=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
SPARC_OIDC_PROVIDER_TITLE=Okta
```

## 6. Test the Integration

1. Start SPARC: `bin/rails server`
2. Navigate to `http://localhost:3000/login`
3. Click the **Okta** tab
4. Click **Sign in with Okta**
5. Authenticate with your Okta credentials
6. You should be redirected back to SPARC and signed in

## 7. Add Test Users

1. In the Okta Admin Console, go to **Directory > People**
2. Click **Add Person**
3. Fill in email, first name, last name
4. Set a password
5. Assign the person to your SPARC application under **Applications**

## 8. Enable MFA (Optional)

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

### Token errors
Ensure the **Issuer URL** points to the correct authorization server. The default is usually `https://dev-XXXXXXXX.okta.com/oauth2/default`.
