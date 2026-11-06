-- Cover the scan-result FK used by lease validation, reuse and cleanup.
CREATE INDEX IF NOT EXISTS receipt_scan_jobs_scan_id ON private.receipt_scan_jobs(scan_id);
