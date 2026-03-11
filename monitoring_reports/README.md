# Certificate Lifecycle Monitoring Reports

## Directory Contents

This directory contains automated monitoring reports and metrics for the OpenBao PKI infrastructure.

### Report Files

- **cert_lifecycle_YYYYMMDD_HHMMSS.txt** - Timestamped monitoring reports
  - Certificate expiration status
  - PKI health checks
  - CRL analysis
  - ACME endpoint status

- **pki_metrics.prom** - Prometheus-format metrics (updated on each run)
  - Current certificate counts
  - Health indicators
  - Ready for Prometheus scraping

### Latest Report

-rw-r--r--@ 1 ismailzemouri  staff  3704 Feb  7 01:52 monitoring_reports/cert_lifecycle_20260207_015207.txt
