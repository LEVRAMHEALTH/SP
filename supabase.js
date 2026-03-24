import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  console.error(
    'Missing Supabase env vars. Create a .env file with:\n' +
    'VITE_SUPABASE_URL=https://your-project.supabase.co\n' +
    'VITE_SUPABASE_ANON_KEY=your-anon-key'
  );
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey);

// ══════════════════════════════════════════
// AUTH FUNCTIONS
// ══════════════════════════════════════════

export async function signIn(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data;
}

export async function signUp(email, password) {
  const { data, error } = await supabase.auth.signUp({ email, password });
  if (error) throw error;
  return data;
}

export async function signOut() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

export async function getSession() {
  const { data: { session } } = await supabase.auth.getSession();
  return session;
}

// ══════════════════════════════════════════
// EMPLOYEE FUNCTIONS
// ══════════════════════════════════════════

export async function getMyEmployee() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  const { data, error } = await supabase
    .from('employees')
    .select('*')
    .eq('auth_user_id', user.id)
    .single();
  if (error) throw error;
  return data;
}

export async function lookupEmployee(empId) {
  const { data, error } = await supabase
    .from('employees')
    .select('*')
    .eq('emp_id', empId.toUpperCase())
    .single();
  if (error && error.code !== 'PGRST116') throw error;
  return data;
}

export async function linkAuthToEmployee(empId, authUserId) {
  const { data, error } = await supabase
    .from('employees')
    .update({ auth_user_id: authUserId })
    .eq('emp_id', empId.toUpperCase())
    .select()
    .single();
  if (error) throw error;
  return data;
}

// ══════════════════════════════════════════
// MONTHLY CLAIMS FUNCTIONS
// ══════════════════════════════════════════

export async function getMyClaims(employeeId) {
  const { data, error } = await supabase
    .from('monthly_claims')
    .select('*')
    .eq('employee_id', employeeId)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data || [];
}

export async function getOrCreateClaim(employeeId, month) {
  // Try to get existing
  let { data } = await supabase
    .from('monthly_claims')
    .select('*')
    .eq('employee_id', employeeId)
    .eq('month', month)
    .single();
  
  if (data) return data;

  // Create new
  const claimNumber = `LV-${new Date().getFullYear()}-${String(Math.floor(Math.random() * 9000) + 1000)}`;
  const { data: newClaim, error } = await supabase
    .from('monthly_claims')
    .insert({ claim_number: claimNumber, employee_id: employeeId, month })
    .select()
    .single();
  if (error) throw error;
  return newClaim;
}

export async function updateClaim(claimId, updates) {
  const { data, error } = await supabase
    .from('monthly_claims')
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq('id', claimId)
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function submitClaim(claimId) {
  return updateClaim(claimId, { 
    status: 'submitted', 
    submitted_at: new Date().toISOString() 
  });
}

// Admin: get all submitted claims
export async function getAllClaims(statusFilter) {
  let query = supabase
    .from('claims_with_employee')
    .select('*')
    .neq('status', 'draft')
    .order('submitted_at', { ascending: false });
  
  if (statusFilter && statusFilter !== 'all') {
    query = query.eq('status', statusFilter);
  }
  
  const { data, error } = await query;
  if (error) throw error;
  return data || [];
}

// Admin: update claim status
export async function reviewClaim(claimId, status, reviewerId, remarks) {
  const { data, error } = await supabase
    .from('monthly_claims')
    .update({ 
      status, 
      reviewed_by: reviewerId, 
      reviewed_at: new Date().toISOString(),
      review_remarks: remarks,
      updated_at: new Date().toISOString()
    })
    .eq('id', claimId)
    .select()
    .single();
  if (error) throw error;
  
  // Log the action
  await addVerificationLog(claimId, null, `claim_${status}`, reviewerId, remarks);
  
  return data;
}

// ══════════════════════════════════════════
// DAILY EXPENSES FUNCTIONS
// ══════════════════════════════════════════

export async function getExpenses(claimId) {
  const { data, error } = await supabase
    .from('expenses_with_files')
    .select('*')
    .eq('claim_id', claimId)
    .order('expense_date', { ascending: false });
  if (error) throw error;
  return data || [];
}

export async function addExpense(expense) {
  const { data, error } = await supabase
    .from('daily_expenses')
    .insert(expense)
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function updateExpense(expenseId, updates) {
  const { data, error } = await supabase
    .from('daily_expenses')
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq('id', expenseId)
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function deleteExpense(expenseId) {
  const { error } = await supabase
    .from('daily_expenses')
    .delete()
    .eq('id', expenseId);
  if (error) throw error;
}

// Admin: verify/reject individual expense
export async function verifyExpense(expenseId, status, verifierId, remarks) {
  const { data, error } = await supabase
    .from('daily_expenses')
    .update({ 
      verified_status: status, 
      verified_by: verifierId,
      verified_at: new Date().toISOString(),
      verification_remarks: remarks
    })
    .eq('id', expenseId)
    .select()
    .single();
  if (error) throw error;
  
  // Log
  await addVerificationLog(null, expenseId, `expense_${status}`, verifierId, remarks);
  
  return data;
}

// ══════════════════════════════════════════
// FILE UPLOAD FUNCTIONS
// ══════════════════════════════════════════

export async function uploadReceipt(expenseId, file) {
  const fileExt = file.name.split('.').pop();
  const filePath = `${expenseId}/${Date.now()}.${fileExt}`;

  // Upload to Supabase Storage
  const { data: uploadData, error: uploadError } = await supabase.storage
    .from('receipts')
    .upload(filePath, file, { 
      cacheControl: '3600',
      upsert: false 
    });
  if (uploadError) throw uploadError;

  // Save file record
  const { data, error } = await supabase
    .from('receipt_files')
    .insert({
      expense_id: expenseId,
      file_name: file.name,
      file_size: file.size,
      file_type: file.type,
      storage_path: filePath
    })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function getReceiptUrl(storagePath) {
  const { data } = await supabase.storage
    .from('receipts')
    .createSignedUrl(storagePath, 3600); // 1 hour expiry
  return data?.signedUrl;
}

export async function deleteReceipt(fileId, storagePath) {
  await supabase.storage.from('receipts').remove([storagePath]);
  await supabase.from('receipt_files').delete().eq('id', fileId);
}

export async function getExpenseFiles(expenseId) {
  const { data, error } = await supabase
    .from('receipt_files')
    .select('*')
    .eq('expense_id', expenseId);
  if (error) throw error;
  return data || [];
}

// ══════════════════════════════════════════
// VERIFICATION LOG FUNCTIONS
// ══════════════════════════════════════════

export async function addVerificationLog(claimId, expenseId, action, performedBy, remarks, metadata) {
  const { error } = await supabase
    .from('verification_logs')
    .insert({
      claim_id: claimId,
      expense_id: expenseId,
      action,
      performed_by: performedBy,
      remarks,
      metadata
    });
  if (error) console.error('Log error:', error);
}

export async function getClaimLogs(claimId) {
  const { data, error } = await supabase
    .from('verification_logs')
    .select(`
      *,
      performer:employees!performed_by(name, emp_id)
    `)
    .eq('claim_id', claimId)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data || [];
}

// ══════════════════════════════════════════
// DASHBOARD STATS (Admin)
// ══════════════════════════════════════════

export async function getDashboardStats() {
  const { data: claims } = await supabase
    .from('monthly_claims')
    .select('status, total_amount')
    .neq('status', 'draft');
  
  if (!claims) return { total: 0, pending: 0, flagged: 0, approved: 0, totalAmount: 0 };
  
  return {
    total: claims.length,
    pending: claims.filter(c => c.status === 'pending' || c.status === 'submitted').length,
    flagged: claims.filter(c => c.status === 'flagged').length,
    approved: claims.filter(c => c.status === 'approved').length,
    totalAmount: claims.reduce((s, c) => s + parseFloat(c.total_amount || 0), 0)
  };
}
