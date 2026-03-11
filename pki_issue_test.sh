#!/bin/bash
set -e

# Configuration
export BAO_ADDR=${BAO_ADDR:-"http://127.0.0.1:8200"}
export BAO_TOKEN=${BAO_TOKEN:-"root"}
BINARY="/opt/homebrew/bin/bao"

echo "--> Testing Certificate Issuance..."

# 1. Issue Smart Meter Certificate
echo "--> Requesting Smart Meter Certificate..."
$BINARY write -format=json pki_int/issue/smart-meter \
    common_name="meter-001.meter.energy.internal" \
    ttl=24h > meter_cert.json
echo "   Success: Smart Meter Certificate Issued"

# 2. Issue SCADA Certificate
echo "--> Requesting SCADA Certificate..."
$BINARY write -format=json pki_int/issue/scada-system \
    common_name="control-unit-01.scada.energy.internal" \
    ttl=24h > scada_cert.json
echo "   Success: SCADA Certificate Issued"

# 3. Issue Corporate User Certificate
echo "--> Requesting Corporate User Certificate..."
$BINARY write -format=json pki_int/issue/corporate-user \
    common_name="employee-123.corp.energy.internal" \
    ttl=8h > user_cert.json
echo "   Success: Corporate User Certificate Issued"

echo "--> Verification Complete: All roles successfully issued certificates."
