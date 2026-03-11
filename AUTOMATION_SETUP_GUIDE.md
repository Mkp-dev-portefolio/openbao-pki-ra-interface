# Automated Certificate Monitoring Setup Guide

## Three Methods to Schedule Automated Monitoring

Choose the method that best fits your environment:

---

## Method 1: Cron (Traditional Unix/Linux)

### Quick Setup

```bash
crontab -e
# Add this line:
0 9 * * * cd /Users/ismailzemouri/OpenBao\ PKI && ./monitor_certificate_lifecycle.sh >> monitoring_reports/cron.log 2>&1
```

### Pros & Cons

- ✅ Works on all Unix-like systems
- ✅ Simple and familiar
- ⚠️ May have issues on macOS with file paths containing spaces
- ⚠️ No built-in logging unless specified

### Verify Installation

```bash
crontab -l  # List all cron jobs
tail -f monitoring_reports/cron.log  # View logs after first run
```

---

## Method 2: macOS LaunchAgent (Recommended for macOS)

### Quick Setup

```bash
chmod +x install_launchagent.sh
./install_launchagent.sh
```

### What It Does

1. Copies `com.openbao.pki.monitoring.plist` to `~/Library/LaunchAgents/`
2. Loads the agent with `launchctl`
3. Schedules daily execution at 9:00 AM
4. Automatically logs to `monitoring_reports/launchd.log`

### Pros & Cons

- ✅ Native macOS solution
- ✅ Handles spaces in paths correctly
- ✅ Automatic logging
- ✅ Survives reboots
- ✅ Better error handling
- ⚠️ macOS-specific (not portable)

### Management Commands

```bash
# Check status
launchctl list | grep openbao

# Test immediately (don't wait for 9 AM)
launchctl start com.openbao.pki.monitoring

# View logs
tail -f monitoring_reports/launchd.log

# Disable
launchctl unload ~/Library/LaunchAgents/com.openbao.pki.monitoring.plist

# Re-enable
launchctl load ~/Library/LaunchAgents/com.openbao.pki.monitoring.plist

# Remove completely
launchctl unload ~/Library/LaunchAgents/com.openbao.pki.monitoring.plist
rm ~/Library/LaunchAgents/com.openbao.pki.monitoring.plist
```

---

## Method 3: Kubernetes CronJob (For Production)

If OpenBao is running in Kubernetes, deploy a CronJob:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pki-lifecycle-monitor
  namespace: openbao
spec:
  schedule: "0 9 * * *"  # Daily at 9 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: openbao
          containers:
          - name: monitor
            image: openbao/openbao:latest
            command:
            - /bin/sh
            - -c
            - |
              apk add --no-cache openssl curl jq
              /scripts/monitor_certificate_lifecycle.sh
            env:
            - name: VAULT_ADDR
              value: "http://openbao.openbao.svc:8200"
            - name: VAULT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: openbao-token
                  key: token
            volumeMounts:
            - name: scripts
              mountPath: /scripts
            - name: reports
              mountPath: /monitoring_reports
          volumes:
          - name: scripts
            configMap:
              name: monitoring-scripts
          - name: reports
            persistentVolumeClaim:
              claimName: monitoring-reports-pvc
          restartPolicy: OnFailure
```

### Setup Commands

```bash
# Create ConfigMap with monitoring script
kubectl create configmap monitoring-scripts \
  --from-file=monitor_certificate_lifecycle.sh \
  -n openbao

# Create PVC for reports
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: monitoring-reports-pvc
  namespace: openbao
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# Deploy CronJob
kubectl apply -f pki-monitoring-cronjob.yaml

# Check status
kubectl get cronjobs -n openbao
kubectl get jobs -n openbao

# View logs
kubectl logs -n openbao job/pki-lifecycle-monitor-<timestamp>
```

---

## Recommended Approach by Environment

| Environment | Recommended Method | Reason |
|-------------|-------------------|---------|
| **macOS Development** | LaunchAgent | Better path handling, logging |
| **Linux Server** | Cron | Native, widely supported |
| **Kubernetes Production** | CronJob | Scalable, cloud-native |
| **Docker** | Docker Cron + Volume | Portable, containerized |

---

## Testing Before Scheduling

Before setting up automation, test the script manually:

```bash
# Test basic execution
./monitor_certificate_lifecycle.sh

# Verify output
ls -lh monitoring_reports/
cat monitoring_reports/cert_lifecycle_*.txt

# Check Prometheus metrics
cat monitoring_reports/pki_metrics.prom

# Verify OpenBao connectivity
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=root
bao status
```

---

## Troubleshooting

### Cron Not Running?

```bash
# Check if cron service is running
sudo launchctl list | grep cron  # macOS
systemctl status cron            # Linux

# Check cron logs
grep CRON /var/log/system.log  # macOS
grep CRON /var/log/syslog      # Linux

# Test script manually
cd /Users/ismailzemouri/OpenBao\ PKI
./monitor_certificate_lifecycle.sh
```

### LaunchAgent Not Working?

```bash
# Check for errors
launchctl list | grep openbao
launchctl error com.openbao.pki.monitoring

# View error log
cat monitoring_reports/launchd.error.log

# Reload agent
launchctl unload ~/Library/LaunchAgents/com.openbao.pki.monitoring.plist
launchctl load ~/Library/LaunchAgents/com.openbao.pki.monitoring.plist
```

### Script Fails with "Permission Denied"?

```bash
chmod +x monitor_certificate_lifecycle.sh
```

### "Command not found: bao"?

```bash
# Ensure bao binary path is correct
which bao
# Update BINARY variable in script if needed
```

---

## Next Steps After Setup

1. **Wait for First Execution** (9 AM next day) or **Test Immediately**:

   ```bash
   # For LaunchAgent:
   launchctl start com.openbao.pki.monitoring
   
   # For Cron (can't force, just run manually):
   ./monitor_certificate_lifecycle.sh
   ```

2. **Verify Logs Generated**:

   ```bash
   tail -f monitoring_reports/cron.log       # Cron
   tail -f monitoring_reports/launchd.log    # LaunchAgent
   ```

3. **Set Up Prometheus** (Optional):
   - Configure Prometheus to scrape `monitoring_reports/pki_metrics.prom`
   - See `Certificate_Lifecycle_Monitoring.confluence` for details

4. **Configure Alerts**:
   - Set up email/Slack notifications for expiring certificates
   - Use Prometheus Alertmanager or custom script

---

## Files Reference

| File | Purpose |
|------|---------|
| `monitor_certificate_lifecycle.sh` | Main monitoring script |
| `setup_monitoring_cron.sh` | Interactive cron setup |
| `com.openbao.pki.monitoring.plist` | macOS LaunchAgent config |
| `install_launchagent.sh` | LaunchAgent installer |
| `AUTOMATION_SETUP_GUIDE.md` | This document |
| `monitoring_reports/` | Output directory |
| `monitoring_reports/cron.log` | Cron execution log |
| `monitoring_reports/launchd.log` | LaunchAgent execution log |
| `monitoring_reports/pki_metrics.prom` | Prometheus metrics |

---

## Summary

**For macOS (Your Current Setup)**: I recommend **LaunchAgent** method:

```bash
chmod +x install_launchagent.sh
./install_launchagent.sh
```

This provides the most reliable scheduling on macOS with proper logging and error handling.
