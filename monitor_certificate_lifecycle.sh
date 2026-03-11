#!/bin/bash
# Certificate Lifecycle Monitoring Script for OpenBao PKI
# Monitors: Issuance, Expiration, Revocation, Storage

set -e

# Configuration
export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-root}"
BAO="/opt/homebrew/bin/bao"
THRESHOLD_DAYS=30  # Alert if cert expires within 30 days
OUTPUT_DIR="./monitoring_reports"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create output directory
mkdir -p "$OUTPUT_DIR"
REPORT_FILE="$OUTPUT_DIR/cert_lifecycle_$(date +%Y%m%d_%H%M%S).txt"

echo "=====================================================" | tee "$REPORT_FILE"
echo "  OpenBao PKI - Certificate Lifecycle Monitor" | tee -a "$REPORT_FILE"
echo "  Report Date: $(date)" | tee -a "$REPORT_FILE"
echo "=====================================================" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# Function to convert seconds to days
seconds_to_days() {
    echo $(( $1 / 86400 ))
}

# Function to check certificate expiration
check_cert_expiration() {
    local cert_file=$1
    local cert_name=$2
    
    if [ ! -f "$cert_file" ]; then
        echo -e "${YELLOW}⚠️  Certificate file not found: $cert_file${NC}"
        return
    fi
    
    echo -e "\n${BLUE}━━━ $cert_name ━━━${NC}" | tee -a "$REPORT_FILE"
    
    # Get certificate details
    local not_after=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
    local not_before=$(openssl x509 -in "$cert_file" -noout -startdate | cut -d= -f2)
    local subject=$(openssl x509 -in "$cert_file" -noout -subject | sed 's/subject=//')
    local issuer=$(openssl x509 -in "$cert_file" -noout -issuer | sed 's/issuer=//')
    local serial=$(openssl x509 -in "$cert_file" -noout -serial | cut -d= -f2)
    
    # Calculate days until expiration
    local expiry_epoch=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" +%s 2>/dev/null || echo "0")
    local current_epoch=$(date +%s)
    local days_remaining=$(( ($expiry_epoch - $current_epoch) / 86400 ))
    
    # Status determination
    local status_icon
    local status_color
    if [ $days_remaining -lt 0 ]; then
        status_icon="❌ EXPIRED"
        status_color=$RED
    elif [ $days_remaining -lt $THRESHOLD_DAYS ]; then
        status_icon="⚠️  EXPIRING SOON"
        status_color=$YELLOW
    else
        status_icon="✅ VALID"
        status_color=$GREEN
    fi
    
    # Output details
    echo -e "${status_color}Status: $status_icon${NC}" | tee -a "$REPORT_FILE"
    echo "Subject: $subject" | tee -a "$REPORT_FILE"
    echo "Issuer: $issuer" | tee -a "$REPORT_FILE"
    echo "Serial: $serial" | tee -a "$REPORT_FILE"
    echo "Valid From: $not_before" | tee -a "$REPORT_FILE"
    echo "Valid Until: $not_after" | tee -a "$REPORT_FILE"
    echo -e "${status_color}Days Remaining: $days_remaining${NC}" | tee -a "$REPORT_FILE"
}

# 1. Check Root CA
echo -e "\n${BLUE}═══════════════════════════════════════════════${NC}" | tee -a "$REPORT_FILE"
echo -e "${BLUE}  1. ROOT CA CERTIFICATE STATUS${NC}" | tee -a "$REPORT_FILE"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}" | tee -a "$REPORT_FILE"

if [ -f "root_ca.crt" ]; then
    check_cert_expiration "root_ca.crt" "Root CA"
else
    echo "Fetching Root CA from OpenBao..." | tee -a "$REPORT_FILE"
    $BAO read -field=certificate pki_root/cert/ca > /tmp/root_ca_temp.crt 2>/dev/null || echo "Failed to fetch Root CA"
    if [ -f "/tmp/root_ca_temp.crt" ]; then
        check_cert_expiration "/tmp/root_ca_temp.crt" "Root CA"
        rm /tmp/root_ca_temp.crt
    fi
fi

# 2. Check Intermediate CA
echo -e "\n${BLUE}═══════════════════════════════════════════════${NC}" | tee -a "$REPORT_FILE"
echo -e "${BLUE}  2. INTERMEDIATE CA CERTIFICATE STATUS${NC}" | tee -a "$REPORT_FILE"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}" | tee -a "$REPORT_FILE"

if [ -f "intermediate.crt" ]; then
    check_cert_expiration "intermediate.crt" "Intermediate CA"
else
    echo "Fetching Intermediate CA from OpenBao..." | tee -a "$REPORT_FILE"
    $BAO read -field=certificate pki_int/cert/ca > /tmp/int_ca_temp.crt 2>/dev/null || echo "Failed to fetch Intermediate CA"
    if [ -f "/tmp/int_ca_temp.crt" ]; then
        check_cert_expiration "/tmp/int_ca_temp.crt" "Intermediate CA"
        rm /tmp/int_ca_temp.crt
    fi
fi

# 3. Check Issued Certificates Storage
echo -e "\n${BLUE}═══════════════════════════════════════════════${NC}" | tee -a "$REPORT_FILE"
echo -e "${BLUE}  3. ISSUED CERTIFICATES TRACKING${NC}" | tee -a "$REPORT_FILE"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}" | tee -a "$REPORT_FILE"

echo "Querying pki_int for issued certificates..." | tee -a "$REPORT_FILE"

# List all certificates (serial numbers)
CERT_LIST=$($BAO list -format=json pki_int/certs 2>/dev/null | jq -r '.[]' || echo "")

if [ -z "$CERT_LIST" ]; then
    echo "No certificates found in storage." | tee -a "$REPORT_FILE"
else
    CERT_COUNT=$(echo "$CERT_LIST" | wc -l | tr -d ' ')
    echo -e "${GREEN}Found $CERT_COUNT issued certificate(s)${NC}" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
    
    # Analyze each certificate
    VALID_COUNT=0
    EXPIRING_COUNT=0
    EXPIRED_COUNT=0
    
    for SERIAL in $CERT_LIST; do
        echo -e "\n${BLUE}━━━ Certificate Serial: $SERIAL ━━━${NC}" | tee -a "$REPORT_FILE"
        
        CERT_DATA=$($BAO read -format=json pki_int/cert/$SERIAL 2>/dev/null)
        if [ $? -eq 0 ]; then
            CERT_PEM=$(echo "$CERT_DATA" | jq -r '.data.certificate')
            echo "$CERT_PEM" > /tmp/cert_${SERIAL}.pem
            
            # Get expiration
            NOT_AFTER=$(openssl x509 -in /tmp/cert_${SERIAL}.pem -noout -enddate | cut -d= -f2)
            SUBJECT=$(openssl x509 -in /tmp/cert_${SERIAL}.pem -noout -subject | sed 's/subject=//')
            
            EXPIRY_EPOCH=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$NOT_AFTER" +%s 2>/dev/null || echo "0")
            CURRENT_EPOCH=$(date +%s)
            DAYS_LEFT=$(( ($EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ))
            
            # Categorize
            if [ $DAYS_LEFT -lt 0 ]; then
                STATUS="${RED}❌ EXPIRED${NC}"
                EXPIRED_COUNT=$((EXPIRED_COUNT + 1))
            elif [ $DAYS_LEFT -lt $THRESHOLD_DAYS ]; then
                STATUS="${YELLOW}⚠️  EXPIRING SOON${NC}"
                EXPIRING_COUNT=$((EXPIRING_COUNT + 1))
            else
                STATUS="${GREEN}✅ VALID${NC}"
                VALID_COUNT=$((VALID_COUNT + 1))
            fi
            
            echo -e "Status: $STATUS" | tee -a "$REPORT_FILE"
            echo "Subject: $SUBJECT" | tee -a "$REPORT_FILE"
            echo "Expires: $NOT_AFTER" | tee -a "$REPORT_FILE"
            echo -e "Days Remaining: ${DAYS_LEFT}" | tee -a "$REPORT_FILE"
            
            rm /tmp/cert_${SERIAL}.pem
        fi
    done
    
    # Summary
    echo -e "\n${BLUE}━━━ Certificate Summary ━━━${NC}" | tee -a "$REPORT_FILE"
    echo -e "${GREEN}Valid: $VALID_COUNT${NC}" | tee -a "$REPORT_FILE"
    echo -e "${YELLOW}Expiring Soon (<$THRESHOLD_DAYS days): $EXPIRING_COUNT${NC}" | tee -a "$REPORT_FILE"
    echo -e "${RED}Expired: $EXPIRED_COUNT${NC}" | tee -a "$REPORT_FILE"
fi

# 4. Check CRL (Certificate Revocation List)
echo -e "\n${BLUE}═══════════════════════════════════════════════${NC}" | tee -a "$REPORT_FILE"
echo -e "${BLUE}  4. REVOCATION STATUS (CRL)${NC}" | tee -a "$REPORT_FILE"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}" | tee -a "$REPORT_FILE"

echo "Fetching CRL from pki_int..." | tee -a "$REPORT_FILE"
$BAO read -field=crl pki_int/cert/crl > /tmp/crl.pem 2>/dev/null || echo "No CRL available"

if [ -f "/tmp/crl.pem" ]; then
    CRL_LAST_UPDATE=$(openssl crl -in /tmp/crl.pem -noout -lastupdate | cut -d= -f2)
    CRL_NEXT_UPDATE=$(openssl crl -in /tmp/crl.pem -noout -nextupdate | cut -d= -f2)
    
    echo "CRL Last Update: $CRL_LAST_UPDATE" | tee -a "$REPORT_FILE"
    echo "CRL Next Update: $CRL_NEXT_UPDATE" | tee -a "$REPORT_FILE"
    
    # Count revoked certificates
    REVOKED_COUNT=$(openssl crl -in /tmp/crl.pem -text -noout | grep -c "Serial Number:" || echo "0")
    echo -e "${RED}Revoked Certificates: $REVOKED_COUNT${NC}" | tee -a "$REPORT_FILE"
    
    rm /tmp/crl.pem
fi

# 5. PKI Health Metrics
echo -e "\n${BLUE}═══════════════════════════════════════════════${NC}" | tee -a "$REPORT_FILE"
echo -e "${BLUE}  5. PKI HEALTH METRICS${NC}" | tee -a "$REPORT_FILE"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}" | tee -a "$REPORT_FILE"

# Check if mounts are accessible
echo "Checking PKI mount health..." | tee -a "$REPORT_FILE"

ROOT_HEALTH=$($BAO read pki_root/cert/ca >/dev/null 2>&1 && echo "✅ Healthy" || echo "❌ Unhealthy")
INT_HEALTH=$($BAO read pki_int/cert/ca >/dev/null 2>&1 && echo "✅ Healthy" || echo "❌ Unhealthy")

echo -e "pki_root: $ROOT_HEALTH" | tee -a "$REPORT_FILE"
echo -e "pki_int: $INT_HEALTH" | tee -a "$REPORT_FILE"

# 6. ACME Account Monitoring
echo -e "\n${BLUE}═══════════════════════════════════════════════${NC}" | tee -a "$REPORT_FILE"
echo -e "${BLUE}  6. ACME ACTIVITY${NC}" | tee -a "$REPORT_FILE"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}" | tee -a "$REPORT_FILE"

ACME_DIR_CHECK=$(curl -s http://127.0.0.1:8200/v1/pki_int/acme/directory >/dev/null 2>&1 && echo "✅ Active" || echo "❌ Inactive")
echo -e "ACME Endpoint: $ACME_DIR_CHECK" | tee -a "$REPORT_FILE"

# Final Report Summary
echo -e "\n${BLUE}═══════════════════════════════════════════════${NC}" | tee -a "$REPORT_FILE"
echo -e "${BLUE}  MONITORING SUMMARY${NC}" | tee -a "$REPORT_FILE"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}" | tee -a "$REPORT_FILE"

echo -e "\n✅ Monitoring report generated: $REPORT_FILE" | tee -a "$REPORT_FILE"
echo -e "📊 Threshold for expiration warning: $THRESHOLD_DAYS days" | tee -a "$REPORT_FILE"
echo -e "⏰ Next recommended check: $(date -v+1d)" | tee -a "$REPORT_FILE"

# Export metrics in Prometheus format
METRICS_FILE="$OUTPUT_DIR/pki_metrics.prom"
cat > "$METRICS_FILE" << EOF
# HELP openbao_pki_cert_valid_count Number of valid certificates
# TYPE openbao_pki_cert_valid_count gauge
openbao_pki_cert_valid_count{mount="pki_int"} ${VALID_COUNT:-0}

# HELP openbao_pki_cert_expiring_count Number of certificates expiring soon
# TYPE openbao_pki_cert_expiring_count gauge
openbao_pki_cert_expiring_count{mount="pki_int",threshold_days="$THRESHOLD_DAYS"} ${EXPIRING_COUNT:-0}

# HELP openbao_pki_cert_expired_count Number of expired certificates
# TYPE openbao_pki_cert_expired_count gauge
openbao_pki_cert_expired_count{mount="pki_int"} ${EXPIRED_COUNT:-0}

# HELP openbao_pki_cert_revoked_count Number of revoked certificates
# TYPE openbao_pki_cert_revoked_count gauge
openbao_pki_cert_revoked_count{mount="pki_int"} ${REVOKED_COUNT:-0}

# HELP openbao_pki_mount_health PKI mount health status (1=healthy, 0=unhealthy)
# TYPE openbao_pki_mount_health gauge
openbao_pki_mount_health{mount="pki_root"} $([ "$ROOT_HEALTH" = "✅ Healthy" ] && echo 1 || echo 0)
openbao_pki_mount_health{mount="pki_int"} $([ "$INT_HEALTH" = "✅ Healthy" ] && echo 1 || echo 0)

# HELP openbao_pki_acme_endpoint_health ACME endpoint health (1=active, 0=inactive)
# TYPE openbao_pki_acme_endpoint_health gauge
openbao_pki_acme_endpoint_health{mount="pki_int"} $([ "$ACME_DIR_CHECK" = "✅ Active" ] && echo 1 || echo 0)
EOF

echo -e "\n📈 Prometheus metrics exported: $METRICS_FILE"

echo -e "\n${GREEN}✅ Certificate Lifecycle Monitoring Complete!${NC}"
