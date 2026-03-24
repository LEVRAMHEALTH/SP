-- ══════════════════════════════════════════════════════════════
-- LEVRAM LIFESCIENCES — TRAVEL REIMBURSEMENT DATABASE SCHEMA
-- Run this in Supabase SQL Editor (supabase.com → your project → SQL Editor)
-- ══════════════════════════════════════════════════════════════

-- 1. EMPLOYEES TABLE
-- Master directory of all employees with grades and base info
CREATE TABLE employees (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  emp_id TEXT UNIQUE NOT NULL,           -- e.g. EMP-1001
  name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  phone TEXT,
  grade TEXT NOT NULL CHECK (grade IN ('executive', 'middle', 'top')),
  region TEXT NOT NULL,
  department TEXT,
  role TEXT NOT NULL DEFAULT 'sales' CHECK (role IN ('sales', 'admin', 'manager')),
  is_active BOOLEAN DEFAULT true,
  auth_user_id UUID REFERENCES auth.users(id),  -- links to Supabase Auth
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. MONTHLY CLAIMS TABLE
-- One record per employee per month — the "claim envelope"
CREATE TABLE monthly_claims (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  claim_number TEXT UNIQUE NOT NULL,      -- e.g. LV-2026-0041
  employee_id UUID REFERENCES employees(id) NOT NULL,
  month TEXT NOT NULL,                    -- e.g. "March 2026"
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'submitted', 'pending', 'approved', 'rejected', 'flagged')),
  visit_type TEXT,                        -- "Local Visit" or "On Tour (Outstation)"
  visit_city TEXT,
  purpose TEXT,
  travel_route TEXT,
  notes TEXT,
  total_amount DECIMAL(12,2) DEFAULT 0,
  submitted_at TIMESTAMPTZ,
  reviewed_by UUID REFERENCES employees(id),
  reviewed_at TIMESTAMPTZ,
  review_remarks TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  UNIQUE(employee_id, month)             -- one claim per employee per month
);

-- 3. DAILY EXPENSES TABLE
-- Individual expense line items (daily entries)
CREATE TABLE daily_expenses (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  claim_id UUID REFERENCES monthly_claims(id) ON DELETE CASCADE NOT NULL,
  employee_id UUID REFERENCES employees(id) NOT NULL,
  expense_date DATE NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('da', 'lodge', 'ticket', 'cab', 'vehicle', 'misc')),
  sub_type TEXT,                          -- e.g. "3 Tier AC", "Bus", "Petrol"
  description TEXT NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  auto_calculated BOOLEAN DEFAULT false,  -- true for DA (auto-calc per policy)
  
  -- Category-specific fields
  from_city TEXT,
  to_city TEXT,
  num_days INTEGER DEFAULT 1,
  km_driven DECIMAL(8,2),
  vehicle_type TEXT CHECK (vehicle_type IN ('2w', '4w', NULL)),
  visit_type TEXT,                        -- for DA: "Local Visit" or "On Tour"
  misc_type TEXT,                         -- for misc: "Courier", "Stationery", etc.
  
  -- Verification
  verified_status TEXT DEFAULT 'pending' CHECK (verified_status IN ('pending', 'verified', 'rejected')),
  verified_by UUID REFERENCES employees(id),
  verified_at TIMESTAMPTZ,
  verification_remarks TEXT,
  
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 4. RECEIPT FILES TABLE
-- Tracks uploaded files (actual files stored in Supabase Storage)
CREATE TABLE receipt_files (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  expense_id UUID REFERENCES daily_expenses(id) ON DELETE CASCADE NOT NULL,
  file_name TEXT NOT NULL,
  file_size INTEGER,                      -- bytes
  file_type TEXT,                         -- "application/pdf", "image/jpeg", etc.
  storage_path TEXT NOT NULL,             -- path in Supabase Storage bucket
  uploaded_at TIMESTAMPTZ DEFAULT now()
);

-- 5. VERIFICATION / AUDIT LOG
-- Complete audit trail of all admin actions
CREATE TABLE verification_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  claim_id UUID REFERENCES monthly_claims(id),
  expense_id UUID REFERENCES daily_expenses(id),
  action TEXT NOT NULL CHECK (action IN (
    'claim_submitted', 'claim_approved', 'claim_rejected', 'claim_flagged',
    'expense_verified', 'expense_rejected', 'expense_added', 'expense_deleted',
    'file_uploaded', 'file_deleted'
  )),
  performed_by UUID REFERENCES employees(id) NOT NULL,
  old_status TEXT,
  new_status TEXT,
  remarks TEXT,
  metadata JSONB,                         -- any additional data
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ══════════════════════════════════════════════════════════════
-- INDEXES (for performance)
-- ══════════════════════════════════════════════════════════════
CREATE INDEX idx_employees_emp_id ON employees(emp_id);
CREATE INDEX idx_employees_auth_user ON employees(auth_user_id);
CREATE INDEX idx_claims_employee ON monthly_claims(employee_id);
CREATE INDEX idx_claims_status ON monthly_claims(status);
CREATE INDEX idx_claims_month ON monthly_claims(month);
CREATE INDEX idx_expenses_claim ON daily_expenses(claim_id);
CREATE INDEX idx_expenses_date ON daily_expenses(expense_date);
CREATE INDEX idx_receipts_expense ON receipt_files(expense_id);
CREATE INDEX idx_logs_claim ON verification_logs(claim_id);

-- ══════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY (RLS) — so users can only see their own data
-- ══════════════════════════════════════════════════════════════
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE monthly_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE receipt_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE verification_logs ENABLE ROW LEVEL SECURITY;

-- Helper function: get current employee record from auth
CREATE OR REPLACE FUNCTION get_my_employee()
RETURNS employees AS $$
  SELECT * FROM employees WHERE auth_user_id = auth.uid() LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Helper: check if current user is admin
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM employees 
    WHERE auth_user_id = auth.uid() 
    AND role IN ('admin', 'manager')
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- EMPLOYEES: everyone can read (for lookups), only admins can write
CREATE POLICY "employees_read" ON employees FOR SELECT USING (true);
CREATE POLICY "employees_admin_write" ON employees FOR ALL USING (is_admin());

-- MONTHLY CLAIMS: users see own + admins see all
CREATE POLICY "claims_own_read" ON monthly_claims FOR SELECT USING (
  employee_id = (get_my_employee()).id OR is_admin()
);
CREATE POLICY "claims_own_insert" ON monthly_claims FOR INSERT WITH CHECK (
  employee_id = (get_my_employee()).id
);
CREATE POLICY "claims_own_update" ON monthly_claims FOR UPDATE USING (
  employee_id = (get_my_employee()).id OR is_admin()
);

-- DAILY EXPENSES: users see own + admins see all
CREATE POLICY "expenses_own_read" ON daily_expenses FOR SELECT USING (
  employee_id = (get_my_employee()).id OR is_admin()
);
CREATE POLICY "expenses_own_insert" ON daily_expenses FOR INSERT WITH CHECK (
  employee_id = (get_my_employee()).id
);
CREATE POLICY "expenses_own_update" ON daily_expenses FOR UPDATE USING (
  employee_id = (get_my_employee()).id OR is_admin()
);
CREATE POLICY "expenses_own_delete" ON daily_expenses FOR DELETE USING (
  employee_id = (get_my_employee()).id
);

-- RECEIPT FILES: follow parent expense permissions
CREATE POLICY "receipts_read" ON receipt_files FOR SELECT USING (
  expense_id IN (
    SELECT id FROM daily_expenses WHERE employee_id = (get_my_employee()).id
  ) OR is_admin()
);
CREATE POLICY "receipts_insert" ON receipt_files FOR INSERT WITH CHECK (
  expense_id IN (
    SELECT id FROM daily_expenses WHERE employee_id = (get_my_employee()).id
  )
);
CREATE POLICY "receipts_delete" ON receipt_files FOR DELETE USING (
  expense_id IN (
    SELECT id FROM daily_expenses WHERE employee_id = (get_my_employee()).id
  ) OR is_admin()
);

-- VERIFICATION LOGS: admins only write, everyone reads own
CREATE POLICY "logs_read" ON verification_logs FOR SELECT USING (
  claim_id IN (
    SELECT id FROM monthly_claims WHERE employee_id = (get_my_employee()).id
  ) OR is_admin()
);
CREATE POLICY "logs_admin_insert" ON verification_logs FOR INSERT WITH CHECK (is_admin() OR true);

-- ══════════════════════════════════════════════════════════════
-- AUTO-UPDATE CLAIM TOTAL when expenses change
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION update_claim_total()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE monthly_claims 
  SET total_amount = (
    SELECT COALESCE(SUM(amount), 0) 
    FROM daily_expenses 
    WHERE claim_id = COALESCE(NEW.claim_id, OLD.claim_id)
  ),
  updated_at = now()
  WHERE id = COALESCE(NEW.claim_id, OLD.claim_id);
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_update_claim_total
AFTER INSERT OR UPDATE OR DELETE ON daily_expenses
FOR EACH ROW EXECUTE FUNCTION update_claim_total();

-- ══════════════════════════════════════════════════════════════
-- SEED DATA — Initial employees
-- (passwords are set via Supabase Auth, not here)
-- ══════════════════════════════════════════════════════════════
INSERT INTO employees (emp_id, name, email, phone, grade, region, department, role) VALUES
  ('EMP-1001', 'Arjun Mehta',      'arjun.mehta@levram.com',    '9876543210', 'middle',    'Mumbai',     'Sales - West',     'sales'),
  ('EMP-1002', 'Priya Sharma',     'priya.sharma@levram.com',   '9876541234', 'executive', 'Delhi',      'Sales - North',    'sales'),
  ('EMP-1003', 'Ravi Kumar',       'ravi.kumar@levram.com',     '9876549876', 'top',       'Chennai',    'Sales - South',    'sales'),
  ('EMP-1004', 'Sneha Patel',      'sneha.patel@levram.com',    '9123456780', 'executive', 'Ahmedabad',  'Sales - West',     'sales'),
  ('EMP-1005', 'Vikram Singh',     'vikram.singh@levram.com',   '9988776655', 'middle',    'Pune',       'Sales - West',     'sales'),
  ('EMP-1006', 'Anita Desai',      'anita.desai@levram.com',    '9871234560', 'top',       'Mumbai',     'Sales - National', 'sales'),
  ('EMP-1007', 'Rohit Jain',       'rohit.jain@levram.com',     '9765432100', 'executive', 'Kolkata',    'Sales - East',     'sales'),
  ('EMP-1008', 'Meera Nair',       'meera.nair@levram.com',     '9654321098', 'middle',    'Bangalore',  'Sales - South',    'sales'),
  ('EMP-1009', 'Karan Malhotra',   'karan.malhotra@levram.com', '9543210987', 'middle',    'Hyderabad',  'Sales - South',    'sales'),
  ('EMP-1010', 'Pooja Reddy',      'pooja.reddy@levram.com',    '9432109876', 'executive', 'Lucknow',    'Sales - North',    'sales'),
  ('ADMIN-001','Javal Darjee',     'admin@levram.com',          '9999999999', 'top',       'Mumbai',     'Accounts',         'admin'),
  ('ADMIN-002','Finance Team',     'finance@levram.com',        '9999999998', 'top',       'Mumbai',     'Finance',          'admin');

-- ══════════════════════════════════════════════════════════════
-- STORAGE BUCKET for receipt uploads
-- Run this separately in Supabase Dashboard → Storage → New Bucket
-- Or use this SQL:
-- ══════════════════════════════════════════════════════════════
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'receipts', 
  'receipts', 
  false,                    -- private bucket
  10485760,                 -- 10MB max
  ARRAY['image/jpeg', 'image/png', 'image/jpg', 'application/pdf']
);

-- Storage policies
CREATE POLICY "receipts_upload" ON storage.objects FOR INSERT 
WITH CHECK (bucket_id = 'receipts' AND auth.role() = 'authenticated');

CREATE POLICY "receipts_read" ON storage.objects FOR SELECT 
USING (bucket_id = 'receipts' AND auth.role() = 'authenticated');

CREATE POLICY "receipts_delete" ON storage.objects FOR DELETE 
USING (bucket_id = 'receipts' AND auth.role() = 'authenticated');

-- ══════════════════════════════════════════════════════════════
-- USEFUL VIEWS
-- ══════════════════════════════════════════════════════════════

-- View: Claims with employee details (for admin dashboard)
CREATE OR REPLACE VIEW claims_with_employee AS
SELECT 
  mc.*,
  e.emp_id,
  e.name AS employee_name,
  e.email AS employee_email,
  e.phone AS employee_phone,
  e.grade,
  e.region,
  e.department,
  (SELECT COUNT(*) FROM daily_expenses de WHERE de.claim_id = mc.id) AS expense_count,
  (SELECT COUNT(*) FROM daily_expenses de 
   JOIN receipt_files rf ON rf.expense_id = de.id 
   WHERE de.claim_id = mc.id) AS file_count,
  (SELECT COUNT(*) FROM daily_expenses de 
   WHERE de.claim_id = mc.id AND de.verified_status = 'verified') AS verified_count
FROM monthly_claims mc
JOIN employees e ON e.id = mc.employee_id;

-- View: Expenses with file count
CREATE OR REPLACE VIEW expenses_with_files AS
SELECT 
  de.*,
  (SELECT COUNT(*) FROM receipt_files rf WHERE rf.expense_id = de.id) AS file_count,
  (SELECT json_agg(json_build_object(
    'id', rf.id, 'file_name', rf.file_name, 'file_type', rf.file_type, 
    'file_size', rf.file_size, 'storage_path', rf.storage_path
  )) FROM receipt_files rf WHERE rf.expense_id = de.id) AS files
FROM daily_expenses de;
