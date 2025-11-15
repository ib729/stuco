# Security Audit Report - Student Council Payment System (SCPS)

**Date:** 2024  
**Status:** 🔴 Critical Issues Found  

---

## Executive Summary

A comprehensive security audit was performed on the SCPS codebase. **3 CRITICAL** vulnerabilities, **7 MEDIUM** security issues, and **8 BUGS** were identified that require immediate attention before production deployment.

---

## 🔴 CRITICAL SECURITY ISSUES (Fix Immediately!)

### 1. Hardcoded Default Password
**Location:** `web-next/app/actions/users.ts` (line 54)  
**Severity:** CRITICAL  
**Risk:** Authentication bypass, unauthorized access

**Problem:**
```typescript
password: "password123", // Default password
```
When no users exist, the system automatically creates a default user with username "hello@ivanbelousov.com" and password "password123". This is publicly visible in source code.

**Impact:**
- Anyone can log in with these credentials if no users exist
- Automated bots scan for default credentials
- Complete system compromise possible

**Fix:**
- Remove automatic user creation
- Require manual admin setup during installation
- Use environment variable for initial admin password
- Force password change on first login

---

### 2. Weak Password Hashing (SHA-256)
**Location:** `reset_db.py` (line 20-22)  
**Severity:** CRITICAL  
**Risk:** Password compromise via rainbow tables

**Problem:**
```python
def hash_password(password):
    """Simple password hashing (consider using bcrypt in production)"""
    return hashlib.sha256(password.encode()).hexdigest()
```
SHA-256 is NOT designed for password hashing. It's too fast, making brute-force attacks feasible.

**Impact:**
- Passwords can be cracked quickly using rainbow tables
- No salt means identical passwords have identical hashes
- GPU-accelerated attacks are very effective

**Fix:**
```python
import bcrypt

def hash_password(password):
    salt = bcrypt.gensalt(rounds=12)
    return bcrypt.hashpw(password.encode(), salt)
```

**Note:** The Next.js side uses bcrypt correctly (`web-next/lib/repositories/users.ts`), but the Python reset script doesn't!

---

### 3. Database Query Logging (Information Leakage)
**Location:** `web-next/lib/db.ts` (line 31)  
**Severity:** CRITICAL  
**Risk:** Sensitive data exposure in logs

**Problem:**
```typescript
db = new Database(dbPath, { verbose: console.log });
```
This logs EVERY SQL query with ALL parameters to the console, including:
- Passwords (even if hashed)
- Card UIDs
- Student names
- Transaction amounts
- Everything in the database

**Impact:**
- Sensitive data visible in application logs
- Log files become a treasure trove for attackers
- Compliance violations (GDPR, FERPA)
- Performance degradation

**Fix:**
```typescript
// Production: No verbose logging
db = new Database(dbPath, {
  verbose: process.env.NODE_ENV === 'development' ? console.log : undefined
});

// Better: Use proper structured logging
// db = new Database(dbPath);
```

---

## ⚠️ MEDIUM SECURITY ISSUES

### 4. Optional Authentication for NFC Tap Endpoint
**Location:** `web-next/app/api/nfc/tap/route.ts` (line 25-32)  
**Severity:** MEDIUM  
**Risk:** Unauthorized tap event injection

**Problem:**
```typescript
const expectedSecret = process.env.NFC_TAP_SECRET;
if (expectedSecret && validated.secret !== expectedSecret) {
  // Only checks if expectedSecret exists
}
```
If `NFC_TAP_SECRET` environment variable is not set, anyone can send tap events.

**Impact:**
- Fake transactions could be injected
- Denial of service by flooding with tap events
- Confusion and trust issues

**Fix:**
- Make authentication mandatory
- Fail to start if secret is not configured
- Add rate limiting (see issue #5)

---

### 5. No Rate Limiting
**Location:** All API endpoints and Python scripts  
**Severity:** MEDIUM  
**Risk:** Denial of Service, brute force attacks

**Problem:**
No rate limiting on:
- `/api/nfc/tap` endpoint
- POS checkout actions
- Top-up actions  
- Authentication attempts
- Search queries

**Impact:**
- API abuse and DoS attacks
- Brute force password attacks
- Resource exhaustion
- Service unavailability

**Fix:**
- Implement rate limiting middleware
- Use tools like `express-rate-limit` or `next-rate-limit`
- Python scripts: Add cooldown between operations
- Example:
```typescript
import rateLimit from 'express-rate-limit';

const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});
```

---

### 6. Dynamic SQL Construction
**Location:** `web-next/lib/repositories/users.ts` (line 82-86)  
**Severity:** MEDIUM  
**Risk:** Potential SQL injection (currently mitigated)

**Problem:**
```typescript
const stmt = this.db.prepare(`
  UPDATE users
  SET ${updates.join(", ")}
  WHERE id = ?
`);
```
Dynamic SQL construction, though currently safe because `updates` array is controlled.

**Impact:**
- If future developer adds user-controlled values to `updates`, SQL injection possible
- Fragile security that depends on correct usage

**Fix:**
- Use an ORM or query builder
- Document the security requirement clearly
- Add validation that `updates` only contains safe column names

---

### 7. No Input Validation on Prices (Python Scripts)
**Location:** `pos.py`, `topup.py`  
**Severity:** MEDIUM  
**Risk:** Invalid transactions, potential abuse

**Problem:**
```python
ap.add_argument("price", type=float, help="price per tap in CNY")
```
No validation on the price argument. Negative, zero, or extremely large values not checked.

**Impact:**
- Negative prices could add money instead of deducting
- Extremely large values could cause integer overflow
- Zero price transactions clutter the database

**Fix:**
```python
args = ap.parse_args()
if args.price <= 0:
    print("Error: Price must be positive")
    sys.exit(1)
if args.price > 10000:  # reasonable max
    print("Error: Price exceeds maximum allowed")
    sys.exit(1)
```

---

### 8. Database Path Traversal (Potential)
**Location:** `web-next/lib/db.ts` (line 6)  
**Severity:** MEDIUM  
**Risk:** File system access outside intended directory

**Problem:**
```typescript
const envDbPath = process.env.DATABASE_PATH?.trim();
```
Uses environment variable directly without validation. Could potentially point to sensitive files.

**Impact:**
- If attacker controls environment variables (rare but possible in some hosting scenarios)
- Could read arbitrary SQLite files
- Information disclosure

**Fix:**
```typescript
const envDbPath = process.env.DATABASE_PATH?.trim();
if (envDbPath) {
  // Validate it ends with .db and doesn't contain path traversal
  if (!envDbPath.endsWith('.db') || envDbPath.includes('..')) {
    throw new Error('Invalid DATABASE_PATH');
  }
  // Ensure it's within allowed directories
  const resolvedPath = path.resolve(envDbPath);
  const allowedBase = path.resolve(process.cwd());
  if (!resolvedPath.startsWith(allowedBase)) {
    throw new Error('DATABASE_PATH must be within project directory');
  }
}
```

---

### 9. Authentication Bypass via Auto-User-Creation
**Location:** `web-next/app/actions/users.ts` (line 36-55)  
**Severity:** MEDIUM  
**Risk:** Unintended authentication bypass

**Problem:**
```typescript
const users = usersRepo.findAll();
if (users.length > 0) {
  return users[0]; // Returns first user
}
// No users exist, create a default one
```
System automatically creates and returns a user if none exist.

**Impact:**
- Deleting all users creates a new default user
- No proper authentication enforcement during setup
- Could bypass intended security model

**Fix:**
- Remove auto-creation logic
- Return error if no users exist
- Require explicit admin setup via CLI tool

---

### 10. Subprocess Command Injection Risk
**Location:** `tap-broadcaster.py` (line 120-124)  
**Severity:** LOW-MEDIUM  
**Risk:** Currently safe, but fragile

**Problem:**
```python
result = subprocess.run(
    ["nfc-list"],
    capture_output=True,
    text=True,
    timeout=5
)
```
Uses subprocess with hardcoded command. Currently safe but if device string were passed here, it could be vulnerable.

**Impact:**
- If future changes pass user input to subprocess, command injection possible
- Defense in depth principle suggests additional validation

**Fix:**
- Document that this must NEVER accept user input
- Consider using library calls instead of subprocess
- Add input validation if device parameters are ever added

---

## 🐛 BUGS AND ISSUES

### 11. Race Condition in Card Presence Tracking
**Location:** `tap-broadcaster.py` (line 68 - CardState class)  
**Severity:** LOW  
**Risk:** Duplicate or missed tap events

**Problem:**
Global `card_state` object is not thread-safe. Multiple reader processes could conflict.

**Impact:**
- Duplicate tap events if multiple readers used
- Missed taps due to race conditions
- Inconsistent debouncing

**Fix:**
- Use threading locks
- Or use separate state per reader instance
- Document that multiple readers need separate instances

---

### 12. Integer Overflow on Balance
**Location:** Database schema, all balance operations  
**Severity:** LOW  
**Risk:** Arithmetic overflow with very large balances

**Problem:**
Balance stored as INTEGER (tenths of currency). SQLite INTEGER is 64-bit signed (-9,223,372,036,854,775,808 to 9,223,372,036,854,775,807), which is ~922 quadrillion yuan. However, no explicit max validation.

**Impact:**
- Theoretically possible to overflow with repeated top-ups
- JavaScript Number.MAX_SAFE_INTEGER is only 2^53 - 1
- Could cause precision issues

**Fix:**
- Add reasonable maximum balance validation (e.g., 1,000,000 yuan = 10,000,000 tenths)
- Validate before insert/update
```typescript
const MAX_BALANCE = 10_000_000; // 1 million yuan in tenths
if (newBalance > MAX_BALANCE) {
  throw new Error('Balance exceeds maximum allowed');
}
```

---

### 13. Silent Error Handling
**Location:** Multiple files, e.g., `web-next/app/actions/students.ts` (lines 17-19)  
**Severity:** LOW  
**Risk:** Hidden bugs, difficult debugging

**Problem:**
```typescript
} catch {
  return { success: false, error: "Failed to fetch students" };
}
```
Catches all errors without logging them. Makes debugging difficult.

**Impact:**
- Real errors are hidden
- Cannot debug production issues
- No alerting on unexpected failures

**Fix:**
```typescript
} catch (error) {
  console.error('Failed to fetch students:', error);
  // In production: Send to error tracking service
  return { success: false, error: "Failed to fetch students" };
}
```

---

### 14. Timezone Calculation Fallback
**Location:** `pos.py` (line 11-21)  
**Severity:** LOW  
**Risk:** Incorrect overdraft week calculation on Python < 3.9

**Problem:**
Fallback timezone logic for Python < 3.9 uses UTC approximation which doesn't account for DST or actual timezone offset.

**Impact:**
- Overdraft week boundaries incorrect
- Students could get more/less overdraft than intended
- Inconsistent behavior across deployments

**Fix:**
- Require Python >= 3.9
- Or use `pytz` library for proper timezone support
```python
try:
    from zoneinfo import ZoneInfo
except ImportError:
    from pytz import timezone as ZoneInfo  # fallback with proper tz support
```

---

### 15. Missing Transaction Rollback
**Location:** `pos.py` (line 60-61)  
**Severity:** LOW  
**Risk:** Incorrect database state on errors

**Problem:**
```python
cur.execute("BEGIN IMMEDIATE;")
bal_tenths = cur.execute("SELECT balance FROM accounts WHERE student_id=?", (sid,)).fetchone()[0]
```
Starts transaction but if any error occurs after line 61 and before commit, only catches on specific conditions.

**Impact:**
- Database locks could persist
- Inconsistent state possible
- Connection leaks

**Fix:**
- Use try/except around entire transaction
- Ensure rollback on all error paths
```python
try:
    cur.execute("BEGIN IMMEDIATE;")
    # ... transaction operations ...
    con.commit()
except Exception as e:
    con.rollback()
    raise
finally:
    con.close()
```

---

### 16. No Foreign Key Cascade Documentation
**Location:** `migrations/schema.sql` (multiple locations)  
**Severity:** LOW  
**Risk:** Unexpected data loss

**Problem:**
```sql
FOREIGN KEY(student_id) REFERENCES students(id) ON DELETE CASCADE
```
Deleting a student cascades to delete all cards, accounts, transactions. Not documented.

**Impact:**
- Accidental student deletion loses all history
- No way to recover deleted transaction records
- Audit trail is lost

**Fix:**
- Document the cascade behavior prominently
- Consider soft deletes instead
- Add deletion confirmation with warning about data loss
- Keep transaction history even when student deleted

---

### 17. No Maximum UID Length Validation
**Location:** `batch_import_students.py` (line 82-84)  
**Severity:** LOW  
**Risk:** Database errors, inconsistent data

**Problem:**
```python
if len(uid) < 4 or len(uid) > 20:
    errors.append(f"Row {row_num} ({name}): UID length invalid '{uid}' (expected 4-20 chars)")
```
Validates length but no consistency check across the system. Different parts may accept different lengths.

**Impact:**
- Inconsistent validation
- Database errors if UID too long
- NFC reader might produce UIDs outside expected range

**Fix:**
- Define constant MAX_UID_LENGTH used everywhere
- Update schema to enforce: `card_uid TEXT(20) PRIMARY KEY`

---

### 18. WebSocket Authentication Timing Attack
**Location:** `tap-broadcaster.py` (line 256-283)  
**Severity:** LOW  
**Risk:** Secret could be guessed via timing attack

**Problem:**
```python
if data.get("type") == "auth_success":
```
String comparison for authentication could be vulnerable to timing attacks.

**Impact:**
- Attacker could guess secret character by character
- Requires many attempts but theoretically possible

**Fix:**
- Use constant-time comparison
```python
import hmac

def constant_time_compare(a, b):
    return hmac.compare_digest(a, b)
```

---

## 🔧 CONFIGURATION ISSUES

### 19. Insecure Cookies in Development
**Location:** `web-next/lib/auth.ts` (line 39)  
**Severity:** LOW  
**Risk:** Cookie theft in development environments

**Problem:**
```typescript
useSecureCookies: process.env.NODE_ENV === "production",
```
Cookies not marked as Secure in development, allowing transmission over HTTP.

**Impact:**
- Session hijacking in development
- Builds bad security habits
- Could be accidentally deployed

**Fix:**
```typescript
useSecureCookies: true, // Always use secure cookies
// For local dev, use https://localhost with self-signed cert
```

---

### 20. Overly Permissive CORS
**Location:** `web-next/lib/auth.ts` (line 24-28)  
**Severity:** LOW  
**Risk:** Cross-origin attacks

**Problem:**
```typescript
trustedOrigins: [
  "http://localhost:3000",
  "http://localhost:3333",
  "https://scps.ivanbelousov.com",
],
```
Multiple localhost ports could be exploited if attacker controls a local server.

**Impact:**
- Cross-site attacks from malicious localhost applications
- Session hijacking from other local apps

**Fix:**
- Only include necessary origins
- Remove localhost from production builds
- Use environment-specific configuration

---

## 📊 Summary Statistics

| Category | Count |
|----------|-------|
| 🔴 Critical Issues | 3 |
| ⚠️ Medium Issues | 7 |
| 🐛 Bugs | 8 |
| 🔧 Configuration Issues | 2 |
| **Total** | **20** |

---

## ✅ Recommendations Priority

### IMMEDIATE (Do Before Any Production Use)
1. ✅ Remove hardcoded default password
2. ✅ Fix password hashing in reset_db.py
3. ✅ Disable verbose database logging
4. ✅ Make NFC_TAP_SECRET mandatory
5. ✅ Add rate limiting to all endpoints

### HIGH PRIORITY (This Week)
6. Fix dynamic SQL construction
7. Add input validation on prices
8. Remove auto-user-creation
9. Add proper error logging
10. Document foreign key cascades

### MEDIUM PRIORITY (This Month)
11. Add balance maximum validation
12. Fix timezone fallback logic
13. Add database path validation
14. Improve transaction error handling
15. Add constant-time comparison for secrets

### LOW PRIORITY (Good to Have)
16. Add threading locks for card state
17. Enforce UID length constraints
18. Always use secure cookies
19. Restrict CORS in production
20. Consider soft deletes for audit trail

---

## 🛡️ Security Best Practices to Implement

1. **Input Validation**: Validate ALL user inputs at boundaries
2. **Rate Limiting**: Protect all endpoints from abuse
3. **Logging**: Log security events, but not sensitive data
4. **Secrets Management**: Use environment variables, never hardcode
5. **Error Handling**: Log errors server-side, return generic messages to clients
6. **Authentication**: Make security mandatory, not optional
7. **Database**: Use parameterized queries, transactions, and proper error handling
8. **Testing**: Add security tests, fuzzing, and penetration testing
9. **Updates**: Keep dependencies updated, monitor for CVEs
10. **Code Review**: Review all code changes with security in mind

---

## 📝 Positive Security Findings

The following security practices were implemented correctly:

✅ **Parameterized SQL Queries**: All database queries use parameterized statements (no SQL injection)  
✅ **bcrypt for Passwords**: Next.js side uses proper bcrypt hashing  
✅ **Foreign Key Constraints**: Database enforces referential integrity  
✅ **Input Validation with Zod**: TypeScript actions use Zod schemas  
✅ **Database Transactions**: Critical operations use transactions  
✅ **No eval() or exec()**: No dangerous code execution found  
✅ **CSRF Protection**: Next.js server actions have built-in CSRF protection  
✅ **Environment Variables**: Secrets stored in env vars (not in code)  

---

## 🔗 Resources

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Node.js Security Best Practices](https://nodejs.org/en/docs/guides/security/)
- [SQLite Security](https://www.sqlite.org/security.html)
- [Python Security](https://python.readthedocs.io/en/latest/library/security_warnings.html)

---

**Report Generated:** 2024  
**Next Review:** Recommended after fixes are applied
