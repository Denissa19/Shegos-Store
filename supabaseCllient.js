import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://boifqdoojssmofanhxhj.supabase.co'
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJvaWZxZG9vanNzbW9mYW5oeGhqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk0NzY1MDgsImV4cCI6MjA5NTA1MjUwOH0.oOJ4ntJDxiADFaBnGeSggfiDaQLMLeueDAXg7chqA2w'

export const supabase = createClient(supabaseUrl, supabaseAnonKey)