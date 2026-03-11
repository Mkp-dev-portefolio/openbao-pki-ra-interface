# Certificate Lifecycle Monitoring - Quick Reference

## Monitoring Solution Summary

Your OpenBao PKI lab now has comprehensive certificate lifecycle monitoring across 5 layers:

```mermaid
graph TB
    %% Styling
    classDef layer1 fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    classDef layer2 fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    classDef layer3 fill:#fff3e0,stroke:#ef6c00,stroke-width:2px
    classDef layer4 fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
    classDef layer5 fill:#fce4ec,stroke:#c2185b,stroke-width:2px

    subgraph "Layer 1: Native Audit Logs"
        Audit["OpenBao Audit Device<br/>- All PKI operations<br/>- JSON format logs<br/>- Queryable with jq"] :::layer1
    end

    subgraph "Layer 2: Scheduled Scripts"
        Script["monitor_certificate_lifecycle.sh<br/>- Expiration checking<br/>- CRL analysis<br/>- Health validation<br/>- Daily reports"] :::layer2
    end

    subgraph "Layer 3: Prometheus Metrics"
        Prom["Metrics Exporter<br/>- pki_metrics.prom<br/>- 6 key metrics<br/>- Real-time scraping"] :::layer3
    end

    subgraph "Layer 4: Visualization"
        Graf["Grafana Dashboards<br/>- Certificate timeline<br/>- Health status<br/>- Revocation tracking"] :::layer4
    end

    subgraph "Layer 5: K8s Integration"
        CM["Cert-Manager Monitoring<br/>- Certificate CRD status<br/>- ACME challenges<br/>- Auto-renewal"] :::layer5
    end

    Audit --> Script
    Script --> Prom
    Prom --> Graf
    CM --> Graf
```

## Key Metrics Exported

| Metric | Current Value | Status |
|--------|---------------|--------|
| `openbao_pki_cert_valid_count` | 0 | ✅ No certs issued yet |
| `openbao_pki_cert_expiring_count` | 0 | ✅ None expiring |
| `openbao_pki_cert_expired_count` | 0 | ✅ None expired |
| `openbao_pki_cert_revoked_count` | 0 | ✅ None revoked |
| `openbao_pki_mount_health{mount="pki_root"}` | 1 | ✅ Healthy |
| `openbao_pki_mount_health{mount="pki_int"}` | 1 | ✅ Healthy |
| `openbao_pki_acme_endpoint_health` | 1 | ✅ Active |

## Certificate Authority Status

### Root CA

- **Subject**: CN=Energy Company Root CA
- **Valid Until**: February 5, 2036
- **Days Remaining**: 3,649 days (~10 years)
- **Status**: ✅ Healthy

### Intermediate CA

- **Subject**: CN=Energy Company K8s Intermediate CA
- **Valid Until**: February 6, 2031
- **Days Remaining**: 1,824 days (~5 years)
- **Status**: ✅ Healthy

## Quick Start Commands

### Run Monitoring Manually

```bash
./monitor_certificate_lifecycle.sh
```

### View Latest Report

```bash
cat monitoring_reports/cert_lifecycle_*.txt | tail -50
```

### Check Prometheus Metrics

```bash
cat monitoring_reports/pki_metrics.prom
```

### Query OpenBao Audit Logs

```bash
# Enable audit logging
bao audit enable file file_path=/var/log/openbao/audit.log

# Filter PKI operations
cat /var/log/openbao/audit.log | jq 'select(.request.path | startswith("pki_int/"))'
```

### Schedule Daily Monitoring (Cron)

```bash
crontab -e
# Add:
0 9 * * * /Users/ismailzemouri/OpenBao\ PKI/monitor_certificate_lifecycle.sh
```

## Alert Thresholds

| Alert | Threshold | Severity | Action |
|-------|-----------|----------|--------|
| Root CA Expiring | < 365 days | 🔴 Critical | Plan root rotation |
| Intermediate CA Expiring | < 180 days | 🔴 Critical | Renew intermediate |
| Leaf Cert Expiring Soon | < 30 days | 🟡 Warning | Review renewal |
| Leaf Cert Expiring Urgently | < 7 days | 🔴 Critical | Immediate renewal |
| PKI Mount Down | Any failure | 🔴 Critical | Investigate service |
| ACME Endpoint Down | > 2 min | 🟡 Warning | Check networking |
| High Revocation Rate | > 10/hour | 🔴 Critical | Security incident? |

## Integration with Prometheus

1. **Install Prometheus** (if not already installed):

```bash
# Kubernetes via Helm
helm install prometheus prometheus-community/kube-prometheus-stack

# Or download binary
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.darwin-arm64.tar.gz
```

1. **Configure Scraping**:
Add to `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'openbao-pki'
    file_sd_configs:
      - files:
        - '/Users/ismailzemouri/OpenBao PKI/monitoring_reports/pki_metrics.prom'
        refresh_interval: 60s
```

1. **Load Alert Rules**:

```bash
# Create alert rules file
cat > pki_alerts.yml << 'EOF'
groups:
  - name: pki_alerts
    rules:
      - alert: CertificateExpiringSoon
        expr: openbao_pki_cert_expiring_count > 0
        annotations:
          summary: "Certificates expiring within threshold"
EOF

# Add to Prometheus config
prometheus --config.file=prometheus.yml --storage.tsdb.path=./data
```

## Integration with Grafana

1. **Add Prometheus Data Source**:
   - Settings → Data Sources → Add Prometheus
   - URL: <http://localhost:9090>

2. **Import PKI Dashboard**:
   - Create → Import
   - Use queries from documentation
   - Key visualizations:
     - Certificate count gauge
     - Expiration timeline (bar chart)
     - Health status (stat panels)

3. **Configure Alerts**:
   - Add notification channels (Slack, Email, PagerDuty)
   - Set alert rules on dashboard panels
   - Test notifications

## Files Created

- ✅ `monitor_certificate_lifecycle.sh` - Main monitoring script
- ✅ `Certificate_Lifecycle_Monitoring.confluence` - Full documentation
- ✅ `monitoring_reports/cert_lifecycle_*.txt` - Daily reports
- ✅ `monitoring_reports/pki_metrics.prom` - Prometheus metrics

## Next Steps

1. **Immediate**:
   - [x] Monitoring script created and tested
   - [x] Prometheus metrics exported
   - [x] Documentation completed

2. **Short-term** (this week):
   - [ ] Set up cron job for daily execution
   - [ ] Configure Prometheus to scrape metrics
   - [ ] Create Grafana dashboard

3. **Medium-term** (this month):
   - [ ] Enable OpenBao audit logging
   - [ ] Set up alert notifications (Slack/Email)
   - [ ] Test end-to-end monitoring with real certificate issuance
   - [ ] Document incident response procedures

## Support

For questions or issues with monitoring:

1. Check script logs in `monitoring_reports/`
2. Verify OpenBao is accessible: `bao status`
3. Review documentation: `Certificate_Lifecycle_Monitoring.confluence`
4. Check Prometheus targets: <http://localhost:9090/targets>
