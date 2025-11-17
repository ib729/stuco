# Bug Report - Student Council Payment System (SCPS)

## Critical Bugs 🚨

### 1. **Week Calculation Mismatch Between Python and TypeScript** 
**Location:** `web-next/lib/repositories/overdraft.ts` vs `pos.py`
**Severity:** HIGH - Data Corruption Risk
**Status:** ❌ BROKEN

**The Problem:**
The Python CLI scripts (`pos.py`) and the Next.js web app calculate the week start differently, causing overdraft tracking to be completely out of sync!

- **Python (pos.py):** Correctly calculates Monday 00:00 in Asia/Shanghai timezone, then converts to UTC
  - Result: `2025-11-16 16:00:00` (This is Monday midnight in Shanghai, which is 16:00 UTC)
  
- **TypeScript (overdraft.ts):** Incorrectly uses UTC Monday midnight without timezone conversion
  - Result: `2025-11-17T00:00:00.000Z` (This is Monday midnight UTC, ignoring Shanghai timezone)

**Impact:**
- Students could have different overdraft limits depending on whether they use the Python POS terminal or web interface
- Overdraft usage is tracked in different "weeks" between systems
- Weekly limits won't reset at the same time across systems

**How to Fix:**
Replace the simplified `getCurrentWeekStartUtc()` function in `overdraft.ts` with proper Asia/Shanghai timezone handling using a library like `date-fns-tz` or similar.

---

### 2. **Database Verbose Logging Enabled in Production**
**Location:** `web-next/lib/db.ts` line 31
**Severity:** MEDIUM - Security & Performance Issue
**Status:** ❌ BROKEN

**The Problem:**
```typescript
db = new Database(dbPath, { verbose: console.log });
```

Every single SQL query is being logged to the console!

**Impact:**
- **Security:** Sensitive student data, card UIDs, and balances are logged to console
- **Performance:** Console logging is slow and fills up logs
- **Production:** Logs will be massive and hard to read

**How to Fix:**
Remove the `verbose: console.log` option or only enable it in development:
```typescript
db = new Database(dbPath, { 
  verbose: process.env.NODE_ENV === 'development' ? console.log : undefined 
});
```

---

### 3. **Missing Environment Variable Causes Insecure Auth**
**Location:** Build output and `server.js`
**Severity:** HIGH - Security Issue
**Status:** ⚠️ WARNING

**The Problem:**
Build output shows:
```
ERROR [Better Auth]: You are using the default secret. 
Please set `BETTER_AUTH_SECRET` in your environment variables
```

**Impact:**
- Authentication sessions can be hijacked
- Default secret is publicly known
- System is vulnerable to session forgery

**How to Fix:**
Create a `.env.local` file with a secure random secret:
```bash
BETTER_AUTH_SECRET=your-super-secret-random-string-here
```

---

## Major Bugs 🐛

### 4. **Error Message Shows Raw Database Values (Overdraft Limit)**
**Location:** `web-next/app/actions/pos.ts` line 81
**Severity:** MEDIUM - User Experience Issue
**Status:** ❌ BROKEN

**The Problem:**
```typescript
throw new Error(
  `Insufficient funds. Overdraft limit (¥${student.max_overdraft_week}/week) would be exceeded.`
);
```

The `student.max_overdraft_week` is stored in database "tenths" (e.g., 200 = ¥20.0), but the error message displays it as "200" instead of "20.0".

**Impact:**
- Users see confusing messages like "Overdraft limit (¥200/week)" instead of "¥20.0/week"
- Makes the system look broken or misconfigured

**How to Fix:**
Use the `formatCurrency()` helper:
```typescript
throw new Error(
  `Insufficient funds. Overdraft limit (¥${formatCurrency(student.max_overdraft_week)}/week) would be exceeded.`
);
```

---

### 5. **Low Balance Threshold Hardcoded Without Currency Conversion**
**Location:** Multiple files (e.g., `web-next/app/(app)/students/[id]/page.tsx` lines 63, 73)
**Severity:** MEDIUM - Logic Error
**Status:** ❌ BROKEN

**The Problem:**
```typescript
student.balance <= 50
```

The code checks if balance is <= 50 (tenths), which means ¥5.0. This might be intentional, but it's inconsistent with how other parts of the system work. It should probably check for ¥50.0 (500 tenths) based on typical snack bar spending patterns.

**Impact:**
- "Low Balance" warning triggers at ¥5.0 instead of a more reasonable threshold like ¥50.0
- Makes the warning less useful

**How to Fix:**
Either:
1. Change to `student.balance <= 500` (for ¥50.0 threshold)
2. Or add a comment explaining why ¥5.0 is the intended threshold
3. Or use `toDbValue(50)` to make it clear

---

## Minor Issues ⚠️

### 6. **WebSocket Ping Only for Broadcasters, Not Browser Clients**
**Location:** `web-next/server.js` line 326 comment
**Severity:** LOW - Potential Connection Issue
**Status:** ⚠️ WARNING

**The Problem:**
Comment says: "Browser clients don't need ping keepalive - they maintain connection naturally"

But WebSocket connections CAN timeout without keepalive, especially through proxies or firewalls.

**Impact:**
- Browser clients might disconnect silently
- Real-time tap notifications might stop working
- Users have to refresh the page

**How to Fix:**
Consider adding ping/pong for browser clients too, but with a longer interval (maybe 60s instead of 30s).

---

### 7. **Race Condition in Student Creation**
**Location:** `web-next/lib/repositories/students.ts` lines 51-56
**Severity:** LOW - Edge Case
**Status:** ⚠️ WARNING

**The Problem:**
The transaction creates a student and then creates an account, but uses `.transaction()()` which is unusual.

**Impact:**
- If the account creation fails, you could have a student without an account
- The double function call `db.transaction()()` looks like a mistake

**Verification Needed:**
This might be correct better-sqlite3 syntax, but it looks suspicious. Double-check the documentation.

---

## Configuration Issues ⚙️

### 8. **NFC_TAP_SECRET Environment Variable Warning**
**Location:** `server.js` line 244
**Severity:** MEDIUM - Security in Production
**Status:** ⚠️ WARNING

**The Problem:**
```javascript
if (!expectedSecret) {
  console.warn(`NFC_TAP_SECRET not configured - allowing broadcaster (INSECURE!)`);
}
```

In production, if `NFC_TAP_SECRET` is not set, the system allows ANY WebSocket connection to broadcast tap events.

**Impact:**
- Anyone can send fake card tap events
- No authentication for the Python tap-broadcaster
- Could be exploited to make fake transactions

**How to Fix:**
Add `NFC_TAP_SECRET` to `.env.local`:
```bash
NFC_TAP_SECRET=your-secret-here-matching-python-script
```

---

## Summary

**Total Issues Found:** 8

**Critical (Must Fix):** 3
- Week calculation mismatch (data corruption risk)
- Database verbose logging (security + performance)
- Missing BETTER_AUTH_SECRET (security)

**Major (Should Fix):** 2
- Error message formatting
- Low balance threshold logic

**Minor (Nice to Fix):** 3
- WebSocket ping for browser clients
- Student creation transaction pattern
- NFC tap secret configuration

## Recommended Priority

1. **URGENT:** Set `BETTER_AUTH_SECRET` and `NFC_TAP_SECRET` in `.env.local`
2. **URGENT:** Fix week calculation mismatch in `overdraft.ts`
3. **HIGH:** Remove database verbose logging
4. **MEDIUM:** Fix error message formatting in `pos.ts`
5. **LOW:** Review other issues as time permits

---

**Generated:** 2025-11-17
**System Version:** SCPS (Next.js 16 + Python CLI)
