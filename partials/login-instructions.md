## Authentication Flow

Read `guardian/config.yaml` for the `authentication` section. If no authentication is configured, skip this entirely.

### Before Testing

Check if you are already logged in by navigating to a protected page. If you can access it, skip the login flow.

### Form-Based Login (login_type: form)

1. Navigate to the `login_url` using Playwright MCP `browser_navigate`
2. Read credentials from `guardian/.env`:
   - `GUARDIAN_USERNAME` for the username/email field
   - `GUARDIAN_PASSWORD` for the password field
3. Follow the `login_flow` steps from config (these are natural language instructions like "Fill email field with $username")
4. Replace `$username` with the GUARDIAN_USERNAME value
5. Replace `$password` with the GUARDIAN_PASSWORD value
6. If a TOTP/MFA step is needed and `GUARDIAN_TOTP_SECRET` is set in `.env`:
   - Generate a TOTP code: run `python3 -c "import pyotp; print(pyotp.TOTP('SECRET_HERE').now())"` via Bash, substituting the actual secret
   - Enter the generated code in the TOTP field
7. Submit the form and wait for navigation

### SSO Login (login_type: sso)

1. Navigate to `login_url`
2. Click the SSO provider button (e.g., "Sign in with Google")
3. Handle the OAuth redirect — you may see:
   - Account selection page: select the correct account
   - Consent page: click "Allow" or "Continue"
   - Redirect back to the application
4. Wait for the redirect to complete

### API Authentication (login_type: api)

1. Read `GUARDIAN_USERNAME` and `GUARDIAN_PASSWORD` (or API key) from `guardian/.env`
2. Obtain a token via the configured auth endpoint (e.g., POST to login URL with credentials)
3. Store the token and include it in subsequent requests as a Bearer token or configured header

### HTTP Basic Auth (login_type: basic)

1. Read `GUARDIAN_USERNAME` and `GUARDIAN_PASSWORD` from `guardian/.env`
2. Include credentials in every request: `curl -u "$username:$password" <url>`

### Verification

After login, verify success using the `success_condition` from config:
- `url_contains`: Check that the current URL includes the specified value
- `url_equals_exactly`: Check that the current URL matches exactly
- `element_present`: Check that a CSS selector is visible on the page
- `text_contains`: Check that the page body contains the specified text

If verification fails, wait 5 seconds and retry once. If it fails again, report the authentication failure and stop.
