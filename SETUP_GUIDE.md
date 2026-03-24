# Levram Travel Reimbursement — Full Stack Setup Guide

## Architecture

```
┌─────────────────┐       ┌──────────────────┐
│   React App     │──────▶│    Supabase      │
│   (Vercel)      │       │                  │
│                 │       │  ☐ Auth (login)   │
│  - Login page   │       │  ☐ PostgreSQL DB  │
│  - Daily entry  │       │  ☐ Storage (files)│
│  - Admin panel  │       │  ☐ Row Security   │
└─────────────────┘       └──────────────────┘
```

---

## STEP 1: Create Supabase Project (5 min)

1. Go to **https://supabase.com** → Click **"Start your project"**
2. Sign up with **GitHub** (use the account you just created)
3. Click **"New Project"**
   - **Organization**: Your default org
   - **Name**: `levram-travel`
   - **Database Password**: Choose a strong password (SAVE THIS!)
   - **Region**: Choose the closest to India (e.g., Mumbai or Singapore)
4. Click **"Create new project"** — wait ~2 minutes for setup

## STEP 2: Run the Database Schema (3 min)

1. In your Supabase dashboard, click **"SQL Editor"** (left sidebar)
2. Click **"New query"**
3. Open the file `supabase/schema.sql` from this project
4. **Copy the ENTIRE content** and paste it into the SQL Editor
5. Click **"Run"** (or Ctrl+Enter)
6. You should see "Success. No rows returned" — that means all tables are created!

**Verify**: Click **"Table Editor"** in the left sidebar. You should see:
- `employees` (12 rows — your seed data)
- `monthly_claims` (empty)
- `daily_expenses` (empty)
- `receipt_files` (empty)
- `verification_logs` (empty)

## STEP 3: Get Your API Keys (1 min)

1. Go to **Settings** → **API** (left sidebar)
2. Copy these two values:
   - **Project URL**: `https://xxxxxxxx.supabase.co`
   - **anon / public key**: `eyJhbGci...` (long string)

## STEP 4: Create User Accounts (5 min)

Each salesperson and admin needs a Supabase Auth account linked to their employee record.

### Option A: Via Supabase Dashboard (easiest for first setup)

1. Go to **Authentication** → **Users** (left sidebar)
2. Click **"Add user"** → **"Create new user"**
3. For each employee, create:

   | Email | Password | Note |
   |-------|----------|------|
   | arjun.mehta@levram.com | (choose password) | EMP-1001, Middle Mgmt |
   | priya.sharma@levram.com | (choose password) | EMP-1002, Executive |
   | ravi.kumar@levram.com | (choose password) | EMP-1003, Top Mgmt |
   | admin@levram.com | (choose password) | Admin account |
   | finance@levram.com | (choose password) | Admin account |

   **Check "Auto Confirm User"** so they can login immediately.

4. After creating each user, you need to **link them to the employee record**.
   Go to **SQL Editor** and run (replace the UUID with the actual auth user ID shown in the Users table):

```sql
-- Link auth users to employees
-- Copy the "User UID" from Authentication → Users for each person

UPDATE employees SET auth_user_id = 'paste-uuid-here' 
WHERE emp_id = 'EMP-1001';

UPDATE employees SET auth_user_id = 'paste-uuid-here' 
WHERE emp_id = 'EMP-1002';

UPDATE employees SET auth_user_id = 'paste-uuid-here' 
WHERE emp_id = 'ADMIN-001';

-- ... repeat for each employee
```

### Option B: Self-Registration (for production)
The app includes a signup flow — salespersons enter their Employee ID + choose a password. The app auto-links their auth account to the employee record.

## STEP 5: Configure Storage Bucket (1 min)

If the schema SQL didn't create the storage bucket automatically:

1. Go to **Storage** (left sidebar)
2. Click **"New bucket"**
   - Name: `receipts`
   - **Public**: OFF (keep private)
   - File size limit: `10MB`
   - Allowed MIME types: `image/jpeg, image/png, image/jpg, application/pdf`
3. Click **"Create bucket"**

## STEP 6: Deploy to Vercel (3 min)

1. Push this project to **GitHub** (same as before)
2. Go to **vercel.com** → Import the repo
3. **IMPORTANT**: Before clicking Deploy, expand **"Environment Variables"** and add:

   | Key | Value |
   |-----|-------|
   | `VITE_SUPABASE_URL` | `https://your-project.supabase.co` |
   | `VITE_SUPABASE_ANON_KEY` | `eyJhbGci...your-anon-key` |

4. Click **Deploy**

## STEP 7: Test It! 🎉

1. Open your Vercel URL
2. Login with one of the email/password combos you created
3. The app auto-detects the employee and their grade
4. Add daily expenses, upload receipts
5. Submit at month-end
6. Login as admin@levram.com to review and approve

---

## Database Schema Overview

### employees
Stores all employee master data. Grade is locked — cannot be changed by the employee.

### monthly_claims
One record per employee per month. Status flow:
```
draft → submitted → pending → approved/rejected/flagged
```

### daily_expenses
Individual expense line items. Each belongs to a monthly_claims record.
Auto-calculates DA based on grade + city + visit type.

### receipt_files
Tracks uploaded files. Actual files are in Supabase Storage bucket `receipts`.

### verification_logs
Complete audit trail. Every action (submit, approve, reject, verify) is logged with who did it and when.

---

## Security

- **Row Level Security (RLS)**: Salespersons can ONLY see their own claims/expenses. Admins see everything.
- **Auth**: Real email/password login via Supabase Auth
- **Storage**: Receipts bucket is private — signed URLs expire in 1 hour
- **Audit trail**: Every action logged in `verification_logs`
- **Auto-calc**: DA amounts are computed server-side based on grade, cannot be manipulated

---

## Useful SQL Queries (run in SQL Editor)

```sql
-- See all pending claims
SELECT * FROM claims_with_employee WHERE status = 'submitted';

-- Monthly expense summary by category
SELECT category, SUM(amount) as total 
FROM daily_expenses 
GROUP BY category 
ORDER BY total DESC;

-- Employee-wise totals for a month
SELECT e.name, e.emp_id, mc.total_amount, mc.status
FROM monthly_claims mc
JOIN employees e ON e.id = mc.employee_id
WHERE mc.month = 'March 2026';

-- Audit trail for a specific claim
SELECT vl.*, e.name as performed_by_name
FROM verification_logs vl
JOIN employees e ON e.id = vl.performed_by
WHERE vl.claim_id = 'claim-uuid-here'
ORDER BY vl.created_at DESC;
```
